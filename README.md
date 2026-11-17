# always-on-claude-box

Turn a small PC with a fresh **Ubuntu Desktop** install into an unattended, always-on box that
runs **Google Chrome with [Claude in Chrome](https://chromewebstore.google.com/detail/fcoeoabgfenejglbffodgkkbkcdhcgfn)**
and **[Claude Desktop](https://code.claude.com/docs/en/desktop-linux)** 24/7. You reach it over
Remote Desktop from your PC or phone, at home or through Tailscale. Anyone who connects first has to
type a PIN, while Claude keeps working in the background.

One interactive script, `install.sh`, asks for everything up front and then does the rest.

> **Why a box at home?** Some websites block traffic from cloud and datacenter IP addresses
> (HTTP 429, CAPTCHAs). A browser running on your own home connection, driven by Claude in
> Chrome, can use those sites as a normal visitor. Scheduled Claude tasks then run there on
> their own, without your main computer.

This is an independent community project. It is not affiliated with or endorsed by Anthropic,
Google or Tailscale.

---

## What you get

| Area | What the installer sets up |
|---|---|
| **Apps** | Google Chrome (Google's apt repo) and Claude Desktop (Anthropic's apt repo; the signing key fingerprint is checked) |
| **Unattended desktop** | GDM auto-login, no sleep/suspend/screen blanking, Chrome and Claude Desktop start at login |
| **Remote Desktop** | GNOME Desktop Sharing over RDP (port 3389) with your own username/password and a self-signed TLS certificate |
| **Headless** | Optional virtual 1920×1080 monitor (EDID override), so GNOME and RDP work with no screen attached |
| **PIN lock** | GNOME Shell extension: an opaque PIN prompt that grabs all input at login, after 5 min idle and on every RDP connect/disconnect. RDP keeps working and Claude keeps running behind it. Escalating lockout and an attempt log |
| **Remote access** | Optional [Tailscale](https://tailscale.com) (WireGuard-based private network, no port forwarding) |
| **Firewall** | `ufw`: SSH (22) and RDP (3389) only from your LAN and Tailscale; every other incoming connection is dropped |
| **SSH hardening** | X11, TCP and agent forwarding off (`/etc/ssh/sshd_config.d/10-always-on-box-hardening.conf`, checked with `sshd -t`); RDP TLS key kept at mode 600 |
| **Self-healing** | Daily reboot at a time you pick; health checks every 5 min (network, GDM, Tailscale, RDP, Chrome, Claude Desktop, disk, temperature); reboot on kernel panic; Intel hardware watchdog |
| **Debloat** | Optional removal of snaps (incl. Firefox), printing, Bluetooth, modem manager, telemetry/crash reporting, VM/cloud tooling and unused desktop apps (≈ 280 packages, ~4 GB) |
| **Monitoring** | Optional `btop` window at login (refresh 3 s, ~1 % CPU) |
| **Housekeeping** | Journal capped at 200 MB, file indexing off, Chrome without the "Restore pages?" bubble and without background-tab throttling |

## Requirements

- **Ubuntu Desktop 26.04 LTS** (GNOME 50), x86_64. The PIN lock extension declares GNOME Shell 50
  only. Other GNOME versions need `shell-version` in `metadata.json` adjusted and re-testing.
- A wired network connection is recommended.
- About 15 GB free disk space after the Ubuntu install; 8 GB RAM or more.
- You run the installer **from the GNOME desktop session** (a terminal on the desktop or over RDP),
  as your normal user. It asks for your sudo password once.

**Tested on:** ASUS Chromebox 3 (Intel Core i7-8550U, 16 GB RAM, 64 GB SSD) with the MrChromebox
UEFI firmware, running Ubuntu 26.04.1 LTS Desktop. Each component was tested on that machine,
including power loss, reboots and the PIN lock over RDP. See [Project status](#project-status).

## Quick start

1. Install **Ubuntu Desktop 26.04 LTS** normally and log in.
2. Get this repository onto the machine (download the ZIP from GitHub, or `git clone` it).
3. In a terminal on the desktop:
   ```bash
   cd always-on-claude-box
   bash install.sh --dry-run   # optional: ask the questions, show every action, change nothing
   bash install.sh
   ```
4. Answer the questions (below), confirm, and wait. If you chose Tailscale, open the login link it
   prints and sign in.
5. Do the [steps after install](#after-install-accounts-and-manual-steps), then `sudo reboot`.

### What the installer asks

All questions come first. Nothing changes until you confirm the summary.

| Question | Default | Notes |
|---|---|---|
| RDP username | your Linux user name | Used by `mstsc` / RDP apps |
| RDP password (twice) | — | At least 8 characters; use a different one from your Ubuntu password |
| PIN (twice) | — | At least 4 characters; stored only as a salted SHA-256 hash |
| Daily reboot time | `03:00` | 24-hour `HH:MM` |
| Install Tailscale? | yes | |
| Tailscale machine name | the hostname | |
| Home LAN (CIDR) | detected from the default route | `none` = SSH/RDP only through Tailscale |
| Turn Wi-Fi off for good? | yes (only asked when on Ethernet) | Blacklists the Wi-Fi driver |
| Remove unneeded software? | yes | See [Debloat](#debloat) |
| Virtual monitor? | yes | Needed for running without a screen |
| btop window at login? | yes | |

Your **sudo password** is asked by `sudo` itself. The installer never stores it, and it never
stores your RDP password or PIN in plain text.

## After install: accounts and manual steps

The installer never signs in to any account for you. At the end it prints this list:

1. **Reboot** (`sudo reboot`). The box logs in by itself and shows the PIN prompt. Chrome, Claude
   Desktop and btop start.
2. **Keyring:** open *Passwords and Keys* (Seahorse), right-click the **Login** keyring, choose
   *Change Password*, type your Ubuntu password, then leave the new password **empty**. With
   auto-login the keyring otherwise stays locked, and Chrome and Claude forget their sign-ins.
   *(Trade-off: anyone with access to your user account can read the saved secrets.)*
3. **Chrome:** optionally sign in to Google, install
   [Claude in Chrome](https://chromewebstore.google.com/detail/fcoeoabgfenejglbffodgkkbkcdhcgfn)
   and sign in to it with your Claude account.
4. **Claude Desktop:** sign in with the same Claude account, turn on Claude in Chrome and create
   your scheduled tasks.
5. **Tailscale** (if installed): in the [admin console](https://login.tailscale.com/admin/machines)
   choose **Disable key expiry** for the box, or it drops off the network after about 6 months.
   Install Tailscale on your PC and phone with the same account.
6. **Router:** reserve the box's LAN address in DHCP.
7. **Power-on after power loss:** check that the machine powers on by itself when power comes
   back. On Chromeboxes with MrChromebox firmware it does by default. Other machines may need a
   BIOS setting ("Restore on AC power loss").

### Connecting

- **Windows:** `mstsc`, computer = Tailscale name (e.g. `mybox`) or LAN IP, then the RDP username
  and password. You see the PIN prompt; type the PIN.
- **Phone:** the Tailscale app plus any RDP client (e.g. Microsoft's *Windows App*).
- **SSH:** `ssh <user>@<tailscale-name>`

## How it works

### Remote Desktop and the PIN lock

GNOME's *Desktop Sharing* mirrors the logged-in session over RDP. Its catch is that **the real GNOME
lock screen blocks Desktop Sharing**: while the session is locked, every RDP connection is refused
(`Session creation inhibited` in the log, `0x204`-style errors on the client). GNOME's *Remote
Login* starts a separate session without your running Chrome and Claude, so it does not help here
either.

So the installer turns the GNOME lock screen off and adds its own **PIN lock** extension
([`files/pinlock@always-on-box/extension.js`](files/pinlock@always-on-box/extension.js)):

- An opaque full-screen layer with a PIN field sits above every window and panel, and a modal
  stage grab (`Shell.ActionMode.LOCK_SCREEN`, like the real lock screen) takes all keyboard and
  mouse input. Super, Alt+Tab, the overview and new windows cannot get past it.
- The session itself stays **unlocked**, so RDP connects and shows the PIN prompt. Chrome, Claude
  in Chrome and Claude Desktop keep running behind it. Chrome starts with
  `--disable-backgrounding-occluded-windows --disable-renderer-backgrounding
  --disable-background-timer-throttling`, so hidden tabs are not slowed down.
- **When it locks:** at login, after 5 minutes without input, whenever an RDP client connects or
  disconnects, and on demand (`pinlock-now`).
- **Wrong PINs** (counted in a row, kept across reboots, reset by the correct PIN):

  | Wrong PIN # | Effect |
  |---|---|
  | 1 | warning only |
  | 2 | input blocked for **30 minutes** |
  | 3 | blocked for **8 hours** |
  | 4 and later | blocked for **24 hours** each |

  While input is blocked, a typed PIN is not checked at all, even the correct one.
- **Every attempt is logged**, including attempts during a lockout, together with the RDP and SSH
  connections open at that moment (Tailscale peers are shown by device name). The log is
  `~/.local/state/pinlock/attempts.log` and the journal:
  ```
  2026-11-17 06:23:24 | WRONG PIN (attempt 1 in a row), warning | connections: RDP from 100.x.y.z (my-pc)
  2026-11-17 06:23:34 | CORRECT PIN, unlocked (earlier wrong attempts: 1) | connections: RDP from 100.x.y.z (my-pc)
  ```
- Texts are Polish when the session language is Polish, and English otherwise.
- **If no PIN file exists, it never locks.** A missing or broken config therefore cannot lock you
  out.

**What it protects against, and what it does not.** The PIN lock stops someone who gets your RDP
credentials (or sits at the HDMI port) from using the desktop, Chrome or Claude. It is **not** a
security boundary against someone with your **Ubuntu account password**: over SSH they can turn it
off (that is the rescue path below). Keep SSH limited to your LAN and Tailscale (the firewall does
this), and consider SSH keys with password login disabled.

### Security review

A read-only review of a box set up this way (privilege escalation, network exposure, file
permissions, authentication) found no path to root and no port reachable from the internet. What
remains is your call, because it needs your keys or your Tailscale account:

| Finding | Severity | What to do |
|---|---|---|
| SSH accepts the account password from the LAN and from every device in your tailnet; that password is also the sudo password | Medium | Add an SSH key, then set `PasswordAuthentication no` (or install `fail2ban`) |
| `ufw` allows all of `tailscale0`, so every tailnet device reaches SSH and RDP | Medium/low | Fine for a one-person tailnet; otherwise restrict 22/3389 with [Tailscale ACLs](https://tailscale.com/kb/1018/acls) |
| The PIN is hashed with a single salted SHA-256; the lockout lives in a user-writable file | Low, by design | Use a longer PIN with letters (`pinlock-set`). It guards against RDP users, not against someone holding the account |
| The RDP certificate is self-signed | Low | Check the fingerprint (`grdctl status`) on first connect |

Fixed by the installer: forwarding is off in SSH, and the RDP TLS key is created with mode 600 (GNOME's own key generation leaves it at 664).

### Self-healing

| Mechanism | Details |
|---|---|
| Daily reboot | `daily-reboot.timer` at your chosen time. It waits up to 30 min if apt/dpkg is busy. No catch-up reboot if the box was off |
| `keepalive-system` (root, every 5 min) | Pings the gateway and 1.1.1.1. After 2 and 4 failures it restarts NetworkManager; after 6 (~30 min offline) it reboots, at most once per 6 h. It also restarts GDM if needed and restarts `tailscaled` if Tailscale is not `Running`. When `/` is over 90 % full it vacuums the journal and runs `apt clean`. It logs warnings at ≥ 90 °C CPU or < 500 MB available RAM |
| `keepalive-user` (session, every 5 min) | Restarts GNOME Remote Desktop, Chrome and Claude Desktop if they are not running. Waits 5 min after boot |
| Kernel | `kernel.panic=10`, `panic_on_oops=1`, `softlockup_panic=1`: reboot 10 s after a panic or lockup |
| Hardware watchdog | Intel TCO (`iTCO_wdt`), with systemd `RuntimeWatchdogSec=60`. A full freeze longer than 60 s triggers a hardware reset. Skipped automatically on machines without it |

Logs: `journalctl -t keepalive -t daily-reboot` and `journalctl --user -t keepalive-user`.

**Watchdog lessons (why the config looks the way it does):**
- Ubuntu deny-lists `iTCO_wdt`, so `/etc/modules-load.d` silently does not load it.
  `watchdog-load.service` loads it by name early in boot and re-executes PID 1 once, so systemd
  picks the device up.
- `RebootWatchdogSec` is set to **off** on purpose. With the default of keeping the watchdog
  running across reboots, the Chromebox either hard-reset ~9 minutes after a clean reboot (the
  driver was not loaded in time) or hung mid-boot with a black screen and no network (the driver
  probed a running timer). With it off, the watchdog stops at shutdown and starts again once the
  system is up.

### Debloat

The debloat step marks the essentials as manually installed, simulates the whole purge with
`apt-get -s`, and stops if apt would install anything or touch GDM, GNOME Shell, Remote Desktop,
Chrome, Claude Desktop, SSH or NetworkManager. Only then does it remove:

- all snaps and `snapd` (pinned so it does not come back); this removes the Snap-based Firefox too
- CUPS and printer drivers, Bluetooth, ModemManager, Avahi, Rygel, OpenVPN, SSSD
- cloud-init, kdump/kexec (frees the `crashkernel` RAM reservation), QEMU
- apport, whoopsie, ubuntu-report, sysstat, update-notifier/update-manager
- Orca, speech-dispatcher, brltty, the first-run wizard and help
- small GNOME apps (Disk Usage, Characters, Clocks, Fonts, Logs, image/PDF viewers, Disks, Calculator)
- CJK input methods, fwupd, switcheroo-control

The full list is in [`modules/20-debloat.sh`](modules/20-debloat.sh). It also disables the
MOTD-news and Ubuntu Pro advertising timers and, if you agree, blacklists the Wi-Fi driver. On the
test machine the Wi-Fi card kept logging PCIe AER errors.

### Virtual monitor

The kernel is told to treat the first HDMI connector as connected (`video=HDMI-A-1:1920x1080@75e`)
and to load a bundled 128-byte EDID (`drm.edid_firmware=...`). The EDID goes into the initramfs
through dracut or initramfs-tools, and the kernel arguments go into
`/etc/default/grub.d/99-virtual-display.cfg`. This requires GRUB. A real monitor plugged in later
still works.

## Everyday commands

| Command | What it does |
|---|---|
| `pinlock-now` | Show the PIN prompt now |
| `pinlock-set` | Change the PIN (also clears the wrong-attempt counter) |
| `pinlock-log [N]` | Last N PIN attempts (default 30) |
| `pinlock-reset` | **Rescue:** lift an active lockout (logged) |
| `pinlock-off` | **Rescue:** disable the PIN lock extension (works over SSH) |
| `systemctl list-timers daily-reboot.timer keepalive-system.timer` | Next reboot and health check |
| `sudo ufw status verbose` | Firewall rules |
| `tailscale status` | Tailscale peers |

## Troubleshooting

- **Locked out by the PIN lockout:** SSH in (LAN or Tailscale) and run `pinlock-reset`, or
  `pinlock-off`.
- **RDP refuses to connect (`0x204`):** check `systemctl --user status gnome-remote-desktop` and
  `sudo ufw status`. Remember that RDP is allowed only from your LAN subnet and Tailscale.
- **Black screen with no network after a reboot:** pull the power and plug it back in. If it happens
  again, check that `/etc/systemd/system.conf.d/90-watchdog.conf` has `RebootWatchdogSec=off`.
- **Chrome or Claude forget sign-ins after a reboot:** the Login keyring still has a password (step 2
  after install).
- **The PIN lock does not appear after install:** GNOME on Wayland loads new extensions only at
  login, so reboot. Check with `gnome-extensions info pinlock@always-on-box`.

## Project status

Every component was built and tested live on the machine above:
- reboots and two controlled power-loss tests (the box powers back on by itself and the filesystem
  is clean)
- RDP over the LAN and over Tailscale
- the PIN lock in an isolated headless GNOME Shell (lock, input grab, wrong and correct PINs, the
  whole lockout sequence, persistence across restarts, the trigger file, both languages) and live
  over RDP
- Claude in Chrome working behind a locked screen

`install.sh` combines those pieces. It passed a full `--dry-run` on that machine, but **a run from a
completely fresh Ubuntu install has not been done yet**. Issues and pull requests are welcome.

## Repository layout

```
install.sh                    interactive installer (questions → summary → install → manual steps)
lib/common.sh                 prompts, dry-run aware helpers
modules/10-base.sh            updates, Chrome, Claude Desktop, auto-login, no sleep, autostart
modules/20-debloat.sh         package/snap removal with an apt simulation guard
modules/30-virtual-display.sh EDID + kernel arguments for headless use
modules/40-remote-desktop.sh  GNOME RDP: TLS cert, credentials, enable
modules/50-tailscale.sh       Tailscale repo, install, login
modules/60-uptime.sh          daily reboot, health checks, panic reboot, hardware watchdog
modules/70-pinlock.sh         PIN lock extension + helper commands
modules/80-firewall.sh        ufw rules
modules/90-monitor.sh         btop window at login
files/                        scripts, extension and configs the modules install
```

## License

[MIT](LICENSE)
