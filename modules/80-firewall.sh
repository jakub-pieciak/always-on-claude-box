# shellcheck shell=bash
# Firewall: SSH and RDP only from the home LAN and Tailscale; drop everything else coming in.

module_firewall() {
  step "Firewall (ufw)"
  run sudo ufw --force reset
  run sudo ufw default deny incoming
  run sudo ufw default allow outgoing
  if [[ "${WITH_TAILSCALE:-false}" == true ]]; then
    run sudo ufw allow in on tailscale0 comment 'Tailscale devices'
    run sudo ufw allow 41641/udp comment 'Tailscale direct connections'
  fi
  if [[ -n "${LAN_SUBNET:-}" ]]; then
    run sudo ufw allow from "$LAN_SUBNET" to any port 22 proto tcp comment 'SSH from LAN'
    run sudo ufw allow from "$LAN_SUBNET" to any port 3389 proto tcp comment 'RDP from LAN'
  fi
  run sudo ufw --force enable
  local ts=""; [[ "${WITH_TAILSCALE:-false}" == true ]] && ts=" and Tailscale"
  ok "Incoming: SSH 22 and RDP 3389 from ${LAN_SUBNET:-nowhere on the LAN}$ts; everything else dropped."
}
