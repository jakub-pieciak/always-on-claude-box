# shellcheck shell=bash
# Performance monitor: btop in its own terminal window, opened at login (refresh 3 s).

module_monitor() {
  step "Performance monitor (btop) at login"
  put "$HOME/.config/btop/btop.conf" 644 < "$REPO_DIR/files/btop.conf"
  put "$HOME/.config/autostart/btop-monitor.desktop" 644 <<'D'
[Desktop Entry]
Type=Application
Name=Performance monitor (btop)
Comment=btop in its own terminal window, started after login
Exec=ptyxis --standalone --new-window -T "Performance monitor" -- btop
Icon=utilities-system-monitor
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=10
D
}
