# shellcheck shell=bash
# PIN lock: a GNOME Shell extension that covers the desktop with a PIN prompt and grabs all input,
# without locking the session (the real lock screen would block Remote Desktop).

PINLOCK_UUID=pinlock@always-on-box

module_pinlock() {
  step "PIN lock"
  local src="$REPO_DIR/files/$PINLOCK_UUID" dst="$HOME/.local/share/gnome-shell/extensions/$PINLOCK_UUID"
  local bin="$HOME/.local/bin" cfg="${XDG_CONFIG_HOME:-$HOME/.config}/pinlock"
  local state="${XDG_STATE_HOME:-$HOME/.local/state}/pinlock"

  run mkdir -p "$cfg" "$state"; run chmod 700 "$cfg" "$state"
  if [[ "${DRY_RUN:-false}" == true ]]; then
    info "+ write $cfg/pin (salted SHA-256 of the PIN)"
  else
    local salt hash
    salt="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    hash="$(printf '%s' "$salt$PIN" | sha256sum | cut -d' ' -f1)"
    (umask 077; printf '%s:%s\n' "$salt" "$hash" > "$cfg/pin")
    rm -f "$cfg/state.json"
  fi

  put "$dst/metadata.json" 644 < "$src/metadata.json"
  put "$dst/extension.js" 644 < "$src/extension.js"
  put "$bin/pinlock-conns" 755 < "$REPO_DIR/files/bin/pinlock-conns"
  put "$bin/pinlock-set" 755 < "$REPO_DIR/files/bin/pinlock-set"
  put "$bin/pinlock-now" 755 <<'S'
#!/bin/sh
# Show the PIN prompt right now.
touch "${XDG_CONFIG_HOME:-$HOME/.config}/pinlock/lock-now"
S
  put "$bin/pinlock-reset" 755 <<'S'
#!/bin/sh
# Rescue (e.g. over SSH): clear the wrong-PIN counter and lift an active lockout.
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/pinlock/state.json"
echo "$(date '+%Y-%m-%d %H:%M:%S') | LOCKOUT CLEARED (pinlock-reset) | connections: $("$HOME/.local/bin/pinlock-conns")" \
  >> "${XDG_STATE_HOME:-$HOME/.local/state}/pinlock/attempts.log"
echo "Lockout cleared."
S
  put "$bin/pinlock-off" 755 <<S
#!/bin/sh
# Rescue (e.g. over SSH): turn the PIN lock off and remove the prompt.
export DBUS_SESSION_BUS_ADDRESS="\${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/\$(id -u)/bus}"
gnome-extensions disable $PINLOCK_UUID && echo "PIN lock off. Back on: gnome-extensions enable $PINLOCK_UUID"
S
  put "$bin/pinlock-log" 755 <<'S'
#!/bin/sh
# Show the last PIN attempts (default 30).
tail -n "${1:-30}" "${XDG_STATE_HOME:-$HOME/.local/state}/pinlock/attempts.log"
S

  run gsettings set org.gnome.shell disable-user-extensions false
  if [[ "${DRY_RUN:-false}" == true ]]; then
    info "+ add $PINLOCK_UUID to org.gnome.shell enabled-extensions"
  else
    python3 - "$PINLOCK_UUID" <<'PY'
import ast, subprocess, sys
uuid = sys.argv[1]
cur = subprocess.run(['gsettings', 'get', 'org.gnome.shell', 'enabled-extensions'],
                     capture_output=True, text=True).stdout.strip()
lst = [] if cur.startswith('@as') else ast.literal_eval(cur)
if uuid not in lst:
    lst.append(uuid)
subprocess.run(['gsettings', 'set', 'org.gnome.shell', 'enabled-extensions', str(lst)], check=True)
PY
  fi
  ok "PIN lock installed; it starts at the next login."
}
