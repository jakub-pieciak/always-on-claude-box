# shellcheck shell=bash
# GNOME Desktop Sharing over RDP (port 3389): mirrors the auto-logged-in session.

module_remote_desktop() {
  step "Remote Desktop (RDP)"
  local dir="$HOME/.local/share/gnome-remote-desktop/certificates"
  if [[ ! -s "$dir/rdp-tls.crt" ]]; then
    run mkdir -p "$dir"
    run openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
      -subj "/CN=$(hostname)" -keyout "$dir/rdp-tls.key" -out "$dir/rdp-tls.crt" 2>/dev/null
  fi
  # also tightens a key GNOME generated earlier (it creates it with mode 664)
  run chmod 600 "$dir/rdp-tls.key"
  run grdctl rdp set-tls-cert "$dir/rdp-tls.crt"
  run grdctl rdp set-tls-key "$dir/rdp-tls.key"
  if [[ "${DRY_RUN:-false}" == true ]]; then
    info "+ grdctl rdp set-credentials <user> <password>"
  else
    grdctl rdp set-credentials "$RDP_USER" "$RDP_PASS"
  fi
  run grdctl rdp disable-view-only
  run grdctl rdp enable
  run systemctl --user enable --now gnome-remote-desktop.service
  ok "RDP user: $RDP_USER (password as typed)"
}
