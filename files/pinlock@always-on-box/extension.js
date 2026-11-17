// PIN lock for an always-on box.
//
// The real GNOME lock screen blocks Desktop Sharing (RDP refuses with "Session creation inhibited").
// This extension instead puts an opaque full-screen layer on top of everything and grabs all
// keyboard/mouse input (like the lock screen does) until the right PIN is typed. The session itself
// stays unlocked, so RDP still connects (and shows the PIN prompt), and background apps such as
// Chrome with Claude in Chrome and Claude Desktop keep running behind it.
//
// Locks: when the extension starts (login), after IDLE_MINUTES without input, whenever a Remote
// Desktop client connects or disconnects, and when ~/.config/pinlock/lock-now appears.
// PIN: ~/.config/pinlock/pin = "<salt>:<sha256(salt + PIN)>" (written by set-pin.sh).
// No PIN file = never locks (safe default). Rescue over SSH: pinlock-off / pinlock-reset.
//
// Wrong PINs (counter survives reboots, reset by the right PIN): 1st = warning only, 2nd = input
// blocked 30 min, 3rd = 8 h, 4th and every later one = 24 h.
// Every attempt (also ones made while blocked) is logged with the Remote Desktop / SSH connections
// active at that moment: ~/.local/state/pinlock/attempts.log and the journal (tag gnome-shell).
// Texts are Polish when the session language is Polish, English otherwise.

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const IDLE_MINUTES = 5;
// lockout after the Nth wrong PIN in a row (seconds); later ones repeat the last value
const LOCKOUT = {2: 30 * 60, 3: 8 * 3600, 4: 24 * 3600};
const LOCKOUT_MAX = 24 * 3600;

const PL = (GLib.get_language_names()[0] || '').startsWith('pl');
const T = PL ? {
    title: 'Zablokowane', hint: 'Wpisz PIN i naciśnij Enter',
    blockedUntil: d => `Wpisywanie zablokowane do ${d}`,
    wrongBlocked: d => `Zły PIN. Wpisywanie zablokowane do ${d}`,
    wrongWarn: 'Zły PIN. Kolejna błędna próba zablokuje wpisywanie na 30 minut.',
    logConns: 'połączenia', logNone: 'brak', logUnreadable: '(nie udało się odczytać)', logNoHelper: '(brak pinlock-conns)',
    logBlocked: d => `PRÓBA W TRAKCIE BLOKADY (do ${d}), PIN nie był sprawdzany`,
    logOk: n => `POPRAWNY PIN, odblokowano (wcześniejsze błędne próby: ${n})`,
    logWrongLock: (n, len, d) => `ZŁY PIN (próba ${n} z rzędu) -> blokada ${len} do ${d}`,
    logWrongWarn: n => `ZŁY PIN (próba ${n} z rzędu), ostrzeżenie`,
} : {
    title: 'Locked', hint: 'Type the PIN and press Enter',
    blockedUntil: d => `Input blocked until ${d}`,
    wrongBlocked: d => `Wrong PIN. Input blocked until ${d}`,
    wrongWarn: 'Wrong PIN. One more wrong attempt blocks input for 30 minutes.',
    logConns: 'connections', logNone: 'none', logUnreadable: '(could not read)', logNoHelper: '(pinlock-conns missing)',
    logBlocked: d => `ATTEMPT DURING LOCKOUT (until ${d}), PIN not checked`,
    logOk: n => `CORRECT PIN, unlocked (earlier wrong attempts: ${n})`,
    logWrongLock: (n, len, d) => `WRONG PIN (attempt ${n} in a row) -> lockout ${len} until ${d}`,
    logWrongWarn: n => `WRONG PIN (attempt ${n} in a row), warning`,
};

export default class PinLockExtension extends Extension {
    enable() {
        this._dir = GLib.build_filenamev([GLib.get_user_config_dir(), 'pinlock']);
        GLib.mkdir_with_parents(this._dir, 0o700);
        this._pinPath = GLib.build_filenamev([this._dir, 'pin']);
        this._triggerPath = GLib.build_filenamev([this._dir, 'lock-now']);
        GLib.unlink(this._triggerPath);   // a stale trigger would never fire CREATED again
        this._overlay = null;
        this._grab = null;
        this._statePath = GLib.build_filenamev([this._dir, 'state.json']);
        const logDir = GLib.build_filenamev([GLib.get_user_state_dir(), 'pinlock']);
        GLib.mkdir_with_parents(logDir, 0o700);
        this._logPath = GLib.build_filenamev([logDir, 'attempts.log']);
        this._connsHelper = GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'pinlock-conns']);
        this._timeouts = new Set();
        this._handles = new Map();

        // lock-now trigger file
        this._monitor = Gio.File.new_for_path(this._dir).monitor_directory(Gio.FileMonitorFlags.NONE, null);
        this._monitorId = this._monitor.connect('changed', (_m, file, _o, ev) => {
            if (file.get_basename() === 'lock-now' &&
                (ev === Gio.FileMonitorEvent.CREATED || ev === Gio.FileMonitorEvent.CHANGES_DONE_HINT)) {
                try { file.delete(null); } catch (e) {}
                this._lock('lock-now');
            }
        });

        // idle
        this._idleMonitor = global.backend.get_core_idle_monitor();
        this._idleWatch = this._idleMonitor.add_idle_watch(IDLE_MINUTES * 60 * 1000, () => this._lock('idle'));

        // Remote Desktop connect / disconnect
        this._rac = global.backend.get_remote_access_controller();
        if (this._rac) {
            this._racId = this._rac.connect('new-handle', (_c, handle) => {
                const stoppedId = handle.connect('stopped', () => {
                    handle.disconnect(stoppedId);
                    this._handles.delete(handle);
                    this._lock('remote session ended');
                });
                this._handles.set(handle, stoppedId);
                this._lock('remote session started');
            });
        }

        // lock right away at login (once the shell is up)
        if (Main.layoutManager._startingUp)
            this._startupId = Main.layoutManager.connect('startup-complete', () => this._lock('login'));
        else
            this._later(1, () => this._lock('enabled'));
    }

    disable() {
        // Note: GNOME disables extensions while the real lock screen is up; this one is only ever
        // disabled on purpose (gnome-extensions disable) or at logout.
        this._unlock();
        for (const id of this._timeouts) GLib.source_remove(id);
        this._timeouts.clear();
        if (this._startupId) Main.layoutManager.disconnect(this._startupId);
        if (this._monitor) { this._monitor.disconnect(this._monitorId); this._monitor.cancel(); }
        if (this._idleWatch) this._idleMonitor.remove_watch(this._idleWatch);
        if (this._rac && this._racId) this._rac.disconnect(this._racId);
        for (const [h, id] of this._handles) { try { h.disconnect(id); } catch (e) {} }
        this._handles.clear();
        this._monitor = this._idleMonitor = this._rac = null;
        this._startupId = this._idleWatch = this._racId = 0;
    }

    _later(seconds, fn) {
        const id = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, seconds, () => {
            this._timeouts.delete(id);
            fn();
            return GLib.SOURCE_REMOVE;
        });
        this._timeouts.add(id);
    }

    _readPin() {
        try {
            const [ok, bytes] = GLib.file_get_contents(this._pinPath);
            if (!ok) return null;
            const [salt, hash] = new TextDecoder().decode(bytes).trim().split(':');
            return salt && hash ? {salt, hash} : null;
        } catch (e) {
            return null;
        }
    }

    _lock(reason) {
        if (!this._readPin()) return;          // no PIN set: do nothing
        if (this._overlay) { this._raise(); return; }
        console.log(`pinlock: locking (${reason})`);

        const overlay = new St.Widget({
            reactive: true,
            can_focus: true,
            layout_manager: new Clutter.BinLayout(),
            style: 'background-color: #101418;',
        });
        overlay.add_constraint(new Clutter.BindConstraint({source: global.stage, coordinate: Clutter.BindCoordinate.ALL}));

        const box = new St.BoxLayout({
            orientation: Clutter.Orientation.VERTICAL,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
            style: 'spacing: 14px; padding: 32px; border-radius: 16px; background-color: #1c2229; min-width: 320px;',
        });
        box.add_child(new St.Label({text: T.title, x_align: Clutter.ActorAlign.CENTER,
            style: 'font-size: 22pt; font-weight: bold; color: #e8eaed;'}));
        box.add_child(new St.Label({text: T.hint, x_align: Clutter.ActorAlign.CENTER,
            style: 'font-size: 12pt; color: #9aa0a6;'}));
        const entry = new St.PasswordEntry({can_focus: true, hint_text: 'PIN', show_peek_icon: false,
            style: 'font-size: 16pt; padding: 8px 12px; min-width: 240px;'});
        box.add_child(entry);
        const msg = new St.Label({text: '', x_align: Clutter.ActorAlign.CENTER,
            style: 'font-size: 11pt; color: #f28b82;'});
        box.add_child(msg);
        overlay.add_child(box);
        this._msg = msg;
        this._showLockout();

        entry.clutter_text.connect('activate', () => this._check(entry, msg));
        // keep focus in the PIN field whatever is clicked
        overlay.connect('button-press-event', () => { entry.grab_key_focus(); return Clutter.EVENT_STOP; });

        Main.uiGroup.add_child(overlay);
        this._overlay = overlay;
        this._entry = entry;
        this._childAddedId = Main.uiGroup.connect('child-added', () => this._raise());
        this._raise();
        this._takeGrab();
    }

    _raise() {
        if (this._overlay) Main.uiGroup.set_child_above_sibling(this._overlay, null);
    }

    _takeGrab() {
        if (!this._overlay || this._grab) return;
        // close the overview and any open menu so nothing else sits on top of our grab
        if (Main.overview.visible) Main.overview.hide();
        Main.panel.closeCalendar?.();
        Main.panel.closeQuickSettings?.();
        // In GNOME 50 a stage grab always succeeds and stacks on top of any other grab.
        this._grab = Main.pushModal(this._overlay, {actionMode: Shell.ActionMode.LOCK_SCREEN});
        this._entry.grab_key_focus();
    }

    // ---- failed-attempt state (persists across reboots)
    _loadState() {
        try {
            const [, bytes] = GLib.file_get_contents(this._statePath);
            const st = JSON.parse(new TextDecoder().decode(bytes));
            return {fails: Number(st.fails) || 0, lockedUntil: Number(st.lockedUntil) || 0};
        } catch (e) {
            return {fails: 0, lockedUntil: 0};
        }
    }

    _saveState(st) {
        try {
            GLib.file_set_contents(this._statePath, JSON.stringify(st));
            GLib.chmod(this._statePath, 0o600);
        } catch (e) {
            console.error(`pinlock: cannot save state: ${e.message}`);
        }
    }

    _now() {
        return Math.floor(GLib.get_real_time() / 1e6);
    }

    _fmt(unix) {
        return GLib.DateTime.new_from_unix_local(unix).format('%d.%m %H:%M');
    }

    _showLockout() {
        if (!this._msg) return;
        const st = this._loadState();
        this._msg.text = st.lockedUntil > this._now()
            ? T.blockedUntil(this._fmt(st.lockedUntil)) : '';
    }

    // ---- logging: every attempt + Remote Desktop / SSH connections active right now
    _log(text) {
        // Entries are queued so they land in the file in the order the attempts happened.
        const stamp = GLib.DateTime.new_now_local().format('%Y-%m-%d %H:%M:%S');
        this._logQueue = (this._logQueue ?? Promise.resolve()).then(() => new Promise(resolve => {
            const write = conns => {
                const line = `${stamp} | ${text} | ${T.logConns}: ${conns || T.logNone}`;
                console.log(`pinlock: ${line}`);
                try {
                    const out = Gio.File.new_for_path(this._logPath)
                        .append_to(Gio.FileCreateFlags.PRIVATE, null);
                    out.write_all(new TextEncoder().encode(`${line}\n`), null);
                    out.close(null);
                } catch (e) {
                    console.error(`pinlock: cannot write log: ${e.message}`);
                }
                resolve();
            };
            try {
                const proc = Gio.Subprocess.new([this._connsHelper],
                    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
                proc.communicate_utf8_async(null, null, (p, res) => {
                    let out = '';
                    try { [, out] = p.communicate_utf8_finish(res); } catch (e) { out = T.logUnreadable; }
                    write((out || '').trim());
                });
            } catch (e) {
                write(T.logNoHelper);
            }
        }));
    }

    _check(entry, msg) {
        const typed = entry.text;
        entry.text = '';
        const now = this._now();
        const st = this._loadState();
        if (st.lockedUntil > now) {
            msg.text = T.blockedUntil(this._fmt(st.lockedUntil));
            this._log(T.logBlocked(this._fmt(st.lockedUntil)));
            return;
        }
        const pin = this._readPin();
        if (!pin) { this._unlock(); return; }
        const hash = GLib.compute_checksum_for_string(GLib.ChecksumType.SHA256, pin.salt + typed, -1);
        if (hash === pin.hash) {
            this._log(T.logOk(st.fails));
            this._saveState({fails: 0, lockedUntil: 0});
            this._unlock();
            return;
        }
        st.fails += 1;
        const secs = LOCKOUT[st.fails] ?? (st.fails > 1 ? LOCKOUT_MAX : 0);
        st.lockedUntil = secs ? now + secs : 0;
        this._saveState(st);
        if (secs) {
            msg.text = T.wrongBlocked(this._fmt(st.lockedUntil));
            this._log(T.logWrongLock(st.fails, secs >= 3600 ? `${secs / 3600} h` : `${secs / 60} min`, this._fmt(st.lockedUntil)));
        } else {
            msg.text = T.wrongWarn;
            this._log(T.logWrongWarn(st.fails));
        }
    }

    _unlock() {
        if (this._grab) { Main.popModal(this._grab); this._grab = null; }
        if (this._childAddedId) { Main.uiGroup.disconnect(this._childAddedId); this._childAddedId = 0; }
        if (this._overlay) { this._overlay.destroy(); this._overlay = null; this._entry = null; this._msg = null; }
    }
}
