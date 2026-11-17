# shellcheck shell=bash
# Base: updates, SSH, Google Chrome, Claude Desktop, no sleep/lock, auto-login, autostart.

module_base() {
  step "Updating the system"
  run sudo apt-get update
  run sudo env DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
  run sudo apt-get install -y curl gnupg openssh-server btop

  step "Adding Google Chrome's apt repository"
  if [[ "${DRY_RUN:-false}" != true ]]; then
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
      | sudo gpg --dearmor --yes -o /usr/share/keyrings/google-chrome.gpg
  else info "+ fetch Google signing key"; fi
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
    | put /etc/apt/sources.list.d/google-chrome.list 644 root

  # https://code.claude.com/docs/en/desktop-linux
  step "Adding Anthropic's apt repository (Claude Desktop)"
  local key=/usr/share/keyrings/claude-desktop-archive-keyring.asc
  local expected=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
  if [[ "${DRY_RUN:-false}" != true ]]; then
    sudo curl -fsSLo "$key" https://downloads.claude.ai/claude-desktop/key.asc
    local fpr; fpr="$(gpg --show-keys --with-colons "$key" | awk -F: '$1=="fpr"{print $10}')"
    if [[ "$fpr" != "$expected" ]]; then
      sudo rm -f "$key"; die "Claude signing key fingerprint mismatch: got '$fpr', expected $expected"
    fi
    ok "Key fingerprint $expected"
  else info "+ fetch and verify Anthropic key $expected"; fi
  echo "deb [arch=amd64,arm64 signed-by=$key] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
    | put /etc/apt/sources.list.d/claude-desktop.list 644 root

  step "Installing Google Chrome and Claude Desktop"
  run sudo apt-get update
  run sudo apt-get install -y google-chrome-stable claude-desktop

  step "Never sleep, never blank, no GNOME lock screen"
  # The GNOME lock screen blocks Desktop Sharing (RDP); the PIN lock module replaces it.
  run sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
  run gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
  run gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
  run gsettings set org.gnome.desktop.session idle-delay 0
  run gsettings set org.gnome.desktop.screensaver lock-enabled false
  run gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend false 2>/dev/null || true

  step "Automatic login for $USER"
  local gdm=/etc/gdm3/custom.conf
  run sudo cp -n "$gdm" "$gdm.bak"
  run sudo sed -i -E '/^\s*#?\s*AutomaticLoginEnable\s*=/d; /^\s*#?\s*AutomaticLogin\s*=/d' "$gdm"
  run sudo sed -i -E "s/^\[daemon\]\s*$/[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$USER/" "$gdm"

  step "Chrome and Claude Desktop start after login"
  # Chrome flags: no "Restore pages?" bubble after a reboot, and no throttling of tabs while the
  # window is hidden (Claude in Chrome keeps working behind the PIN lock).
  local flags="--hide-crash-restore-bubble --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling"
  local as="$HOME/.config/autostart"
  run mkdir -p "$as"
  sed "0,/^Exec=\/usr\/bin\/google-chrome-stable %U/s//Exec=\/usr\/bin\/google-chrome-stable $flags %U/" \
    /usr/share/applications/google-chrome.desktop 2>/dev/null | put "$as/google-chrome.desktop" 644
  local claude_desktop
  claude_desktop="$(grep -l -i '^Exec=.*claude-desktop' /usr/share/applications/*.desktop 2>/dev/null | head -n1 || true)"
  if [[ -n "$claude_desktop" ]]; then put "$as/$(basename "$claude_desktop")" 644 < "$claude_desktop"
  elif [[ "${DRY_RUN:-false}" == true ]]; then info "+ copy Claude Desktop launcher to autostart"
  else warn "Claude Desktop launcher not found; add it in Startup Applications by hand."; fi

  step "Journal capped at 200 MB, file indexing off"
  printf '[Journal]\nSystemMaxUse=200M\n' | put /etc/systemd/journald.conf.d/99-size.conf 644 root
  run sudo systemctl restart systemd-journald
  run systemctl --user mask --now localsearch-3.service localsearch-control-3.service 2>/dev/null || true
  run gsettings set org.freedesktop.Tracker3.Miner.Files index-recursive-directories "[]" 2>/dev/null || true
  run gsettings set org.freedesktop.Tracker3.Miner.Files index-single-directories "[]" 2>/dev/null || true
}
