# shellcheck shell=bash
# Debloat: purge what an unattended browser box does not need (printing, Bluetooth, snaps,
# telemetry, VM/cloud tooling, extra desktop apps). Essentials are marked "manual" first so
# autoremove can never take them, and apt is simulated before anything is removed.

DEBLOAT_KEEP=(
  gdm3 gnome-shell gnome-session ubuntu-session gnome-control-center gnome-settings-daemon
  gnome-remote-desktop gnome-keyring seahorse nautilus ptyxis gnome-text-editor gnome-system-monitor
  network-manager network-manager-gnome wpasupplicant openssh-server
  google-chrome-stable claude-desktop btop
  xdg-desktop-portal-gnome xdg-desktop-portal-gtk pipewire wireplumber
  yaru-theme-gtk yaru-theme-icon fonts-dejavu-core ubuntu-wallpapers
  gnome-shell-extension-appindicator gnome-shell-extension-ubuntu-dock
  thermald chrony cron anacron unattended-upgrades ufw apparmor
  power-profiles-daemon upower udisks2 polkitd
  dracut grub-efi-amd64 grub-efi-amd64-signed shim-signed efibootmgr
  curl gnupg
)

DEBLOAT_REMOVE=(
  # printing
  cups cups-browsed cups-daemon cups-client cups-bsd cups-common bluez-cups hplip
  printer-driver-hpcups libsane-hpaio ipp-usb system-config-printer-common
  # Bluetooth, mobile modem, mDNS/DLNA sharing, VPN, enterprise login
  bluez bluez-obexd gnome-bluetooth-sendto modemmanager mobile-broadband-provider-info
  avahi-daemon rygel openvpn network-manager-openvpn network-manager-openvpn-gnome
  sssd sssd-common
  # cloud / VM / crash dump tooling (kdump also frees its crashkernel RAM reservation)
  cloud-init kdump-tools kexec-tools
  qemu-system-x86 qemu-system-common qemu-system-data qemu-system-gui qemu-utils qemu-block-extra ipxe-qemu
  # telemetry, crash reports, stats, upgrade pop-ups
  apport apport-gtk apport-core-dump-handler whoopsie ubuntu-report sysstat
  update-notifier update-manager
  # accessibility / speech, first-run wizard, help
  brltty orca speech-dispatcher gnome-initial-setup yelp ubuntu-docs gnome-user-docs
  # desktop apps not used on this box
  baobab gnome-characters gnome-clocks gnome-font-viewer gnome-logs loupe papers
  gnome-disk-utility gnome-calculator
  # CJK input methods
  ibus-table-cangjie-big ibus-table-cangjie3 ibus-table-cangjie5 ibus-table
  libchewing3 libchewing3-data libpinyin-data libpinyin15 m17n-db libm17n-0
  libopencc-data libopencc1.1 libotf1 libmarisa1
  # firmware updater, dual-GPU switcher
  fwupd fwupd-signed switcheroo-control
  # snaps (Firefox, Snap Store, ...); Chrome comes from Google's apt repo
  snapd firefox
)

DEBLOAT_SNAPS=(firefox snap-store firmware-updater desktop-security-center prompting-client hwctl
  snapd-desktop-integration gnome-46-2404 gtk-common-themes mesa-2404 core24 bare)

module_debloat() {
  step "Debloat: checking what apt would remove"
  local keep=() rm=() p
  for p in "${DEBLOAT_KEEP[@]}"; do installed "$p" && keep+=("$p+"); done
  for p in "${DEBLOAT_REMOVE[@]}"; do installed "$p" && rm+=("$p"); done
  # keep apt from pulling in a CUPS replacement; also keep every installed language pack
  rm+=("legacy-printer-app-")
  for p in $(dpkg-query -W -f='${Package}\n' 'language-pack-*' 'hunspell-*' 'wpolish' 'wamerican' 2>/dev/null); do
    installed "$p" && keep+=("$p+")
  done
  local sim; sim="$(LC_ALL=C apt-get -s --autoremove purge "${rm[@]}" "${keep[@]}" 2>&1)" \
    || die "apt simulation failed:\n$sim"
  if grep -qE '^(Inst|E:)' <<<"$sim"; then
    grep -E '^(Inst|E:)' <<<"$sim" >&2; die "apt wants to install something during debloat; stopping."
  fi
  info "$(grep -c '^Purg' <<<"$sim") packages will be purged."
  for p in gdm3 gnome-shell gnome-remote-desktop google-chrome-stable claude-desktop openssh-server network-manager; do
    grep -q "^Purg $p " <<<"$sim" && die "Simulation would remove $p; stopping."
  done

  run sudo apt-mark manual "${keep[@]%+}" >/dev/null

  step "Debloat: removing snaps"
  if command -v snap >/dev/null; then
    for p in "${DEBLOAT_SNAPS[@]}"; do
      snap list "$p" >/dev/null 2>&1 && { run sudo snap remove --purge "$p" || true; }
    done
  fi

  step "Debloat: purging packages"
  run sudo env DEBIAN_FRONTEND=noninteractive apt-get -y --autoremove purge "${rm[@]}"
  run sudo rm -rf /var/cache/snapd /var/lib/snapd "$HOME/snap"
  printf 'Package: snapd\nPin: release *\nPin-Priority: -10\n' | put /etc/apt/preferences.d/no-snapd.pref 644 root
  run sudo apt-get -y clean
  run sudo rm -f /etc/default/grub.d/kdump-tools.cfg
  NEED_GRUB=true

  step "Debloat: disabling leftover background jobs"
  for p in motd-news.timer ua-timer.timer apt-news.service esm-cache.service; do
    run sudo systemctl disable --now "$p" 2>/dev/null || true
  done
  run sudo sed -i 's/^ENABLED=1/ENABLED=0/' /etc/default/motd-news 2>/dev/null || true

  if [[ "${DISABLE_WIFI:-false}" == true ]]; then
    step "Turning Wi-Fi off (Ethernet only)"
    run nmcli radio wifi off || true
    for p in $(lspci -k 2>/dev/null | awk '/Network controller/{f=1} f&&/Kernel driver in use/{print $NF; f=0}'); do
      echo "blacklist $p" | put "/etc/modprobe.d/disable-wifi-$p.conf" 644 root
      info "Wi-Fi driver $p blacklisted (undo: delete /etc/modprobe.d/disable-wifi-$p.conf)"
    done
  fi
}
