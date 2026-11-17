# shellcheck shell=bash
# Tailscale: reach the box from anywhere without opening ports on the router.

module_tailscale() {
  step "Tailscale"
  local codename; codename="$(. /etc/os-release; echo "$VERSION_CODENAME")"
  local base=https://pkgs.tailscale.com/stable/ubuntu
  if [[ "${DRY_RUN:-false}" != true ]]; then
    curl -fsSL "$base/$codename.noarmor.gpg" | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
      || die "Tailscale has no repository for '$codename' yet."
    curl -fsSL "$base/$codename.tailscale-keyring.list" | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
  else info "+ add Tailscale repository for $codename"; fi
  run sudo apt-get update
  run sudo apt-get install -y tailscale
  run sudo systemctl enable --now tailscaled
  echo
  info "Tailscale prints a login link now. Open it on any device and sign in."
  info "(The account is yours; this script never sees it.)"
  run sudo tailscale up --operator="$USER" --hostname="$TS_HOSTNAME"
  [[ "${DRY_RUN:-false}" == true ]] || ok "Tailscale address: $(tailscale ip -4 2>/dev/null | head -1)"
}
