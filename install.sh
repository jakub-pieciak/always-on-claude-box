#!/usr/bin/env bash
# always-on-claude-box: turn a fresh Ubuntu Desktop install into an unattended, always-on box that
# runs Google Chrome (with Claude in Chrome) and Claude Desktop 24/7, reachable over Remote Desktop.
#
# Run it from the GNOME desktop session, as the normal user (NOT with sudo):
#     bash install.sh             # interactive install
#     bash install.sh --dry-run   # ask the questions, then only print what would be done
#
# All questions come first; after that the install runs on its own (except the Tailscale login link).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
export DRY_RUN REPO_DIR

# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"
for m in "$REPO_DIR"/modules/*.sh; do
  # shellcheck source=/dev/null
  source "$m"
done

# ------------------------------------------------------------------------------- checks
[[ $EUID -ne 0 ]] || die "Run as your normal user, not root. The script asks for sudo itself."
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die "This is for Ubuntu Desktop (found: ${PRETTY_NAME:-unknown})."
[[ "$(uname -m)" == x86_64 ]] || die "Google Chrome for Linux needs x86_64."
[[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" && "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] \
  || die "Run this from the GNOME desktop session (open Terminal on the desktop or over RDP)."

cat <<EOF

${c_blue}always-on-claude-box${c_off} on $PRETTY_NAME
This sets the computer up as an unattended box for Chrome + Claude Desktop.
Questions first; nothing changes until you confirm at the end.
EOF
$DRY_RUN && warn "DRY RUN: nothing will be changed."
echo

# ------------------------------------------------------------------------------- questions
step "Remote Desktop (RDP) login"
info "Used from Windows (mstsc) / phone RDP apps. Pick a password different from your Ubuntu one."
ask RDP_USER "RDP username" "$USER"
ask_secret RDP_PASS "RDP password (min. 8 characters)" 8

step "PIN lock"
info "Covers the desktop with a PIN prompt at login, after 5 min idle and on every RDP connect."
info "Wrong PINs: 2nd blocks input for 30 min, 3rd for 8 h, 4th and later for 24 h."
ask_secret PIN "PIN (min. 4 characters, digits or letters)" 4

step "Daily reboot"
while true; do
  ask REBOOT_TIME "Reboot every day at (HH:MM, 24 h)" "03:00"
  [[ "$REBOOT_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] && break
  warn "Use HH:MM, e.g. 03:00"
done

step "Remote access over the internet"
ask_yn WITH_TAILSCALE "Install Tailscale (private VPN, no open ports on the router)?" y
TS_HOSTNAME=""
if $WITH_TAILSCALE; then ask TS_HOSTNAME "Name of this computer in Tailscale" "$(hostname | tr '[:upper:].' '[:lower:]-')"; fi

step "Home network"
DEF_IF="$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')"
DEF_NET="$(ip -o -4 route show dev "${DEF_IF:-x}" scope link 2>/dev/null | awk '{print $1; exit}')"
info "SSH and RDP will accept connections only from this LAN$($WITH_TAILSCALE && echo " and Tailscale")."
ask LAN_SUBNET "Home LAN (CIDR), or \"none\" for Tailscale only" "${DEF_NET:-192.168.1.0/24}"
[[ "${LAN_SUBNET,,}" == none ]] && LAN_SUBNET=""
DISABLE_WIFI=false
if [[ "$(nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -c '^ethernet:connected')" -gt 0 ]]; then
  ask_yn DISABLE_WIFI "You are on Ethernet. Turn Wi-Fi off for good (blacklist its driver)?" y
fi

step "Optional parts"
ask_yn WITH_DEBLOAT "Remove unneeded software (snaps, printing, Bluetooth, telemetry, extra apps)?" y
ask_yn WITH_VD "Add a virtual 1920x1080 monitor (needed to run without a screen attached)?" y
ask_yn WITH_MONITOR "Open a btop performance monitor window at login?" y

export RDP_USER RDP_PASS PIN REBOOT_TIME WITH_TAILSCALE TS_HOSTNAME LAN_SUBNET DISABLE_WIFI

step "Summary"
info "RDP user ............ $RDP_USER"
info "PIN ................. (set, ${#PIN} characters)"
info "Daily reboot ........ $REBOOT_TIME"
info "Tailscale ........... $($WITH_TAILSCALE && echo "yes, as '$TS_HOSTNAME'" || echo no)"
info "LAN for SSH/RDP ..... ${LAN_SUBNET:-none}"
info "Wi-Fi off ........... $DISABLE_WIFI"
info "Debloat ............. $WITH_DEBLOAT"
info "Virtual monitor ..... $WITH_VD"
info "btop window ......... $WITH_MONITOR"
ask_yn GO "Start?" y
$GO || die "Cancelled, nothing changed."

# ------------------------------------------------------------------------------- run
if ! $DRY_RUN; then
  sudo -v || die "sudo is needed."
  # keep sudo alive while the install runs
  while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
  SUDO_KEEPALIVE=$!
  trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT
fi

NEED_GRUB=false; NEED_INITRAMFS=false
module_base
$WITH_DEBLOAT && module_debloat
$WITH_VD && module_virtual_display
module_remote_desktop
$WITH_TAILSCALE && module_tailscale
module_uptime
module_pinlock
module_firewall
$WITH_MONITOR && module_monitor
unset RDP_PASS PIN

if $NEED_INITRAMFS; then
  step "Rebuilding the initramfs"
  if command -v dracut >/dev/null; then run sudo dracut -f --regenerate-all
  else run sudo update-initramfs -u -k all; fi
fi
if $NEED_GRUB && command -v update-grub >/dev/null; then
  step "Updating GRUB"; run sudo update-grub
fi

# ------------------------------------------------------------------------------- what is left
TS_IP=""; $WITH_TAILSCALE && ! $DRY_RUN && TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
LAN_IP="$(ip -4 -o addr show dev "${DEF_IF:-x}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
cat <<EOF

${c_green}Done.${c_off} What is left to do by hand (accounts are yours; the script never signs in):

  1. Reboot now:  sudo reboot
     The box logs in by itself and shows the PIN prompt. Chrome, Claude Desktop and btop start.

  2. Keyring: open "Passwords and Keys" (Seahorse), right-click the "Login" keyring,
     Change Password, type your Ubuntu password, then leave the new one EMPTY.
     Without this, auto-login leaves the keyring locked and Chrome/Claude forget sign-ins.

  3. Chrome: sign in to your Google account (optional) and install Claude in Chrome:
     https://chromewebstore.google.com/detail/fcoeoabgfenejglbffodgkkbkcdhcgfn
     then sign in to the extension with your Claude account.

  4. Claude Desktop: sign in with the same Claude account, turn on Claude in Chrome
     in its settings and set up your scheduled tasks.
EOF
if $WITH_TAILSCALE; then cat <<EOF

  5. Tailscale admin console https://login.tailscale.com/admin/machines:
     on "$TS_HOSTNAME" choose "Disable key expiry", or the box drops off in ~6 months.
     Install Tailscale on your PC/phone with the same account.
EOF
fi
cat <<EOF

  6. Router: reserve the box's LAN address in DHCP (now ${LAN_IP:-unknown}).

Connect:  RDP to ${TS_HOSTNAME:-$LAN_IP}${TS_IP:+ ($TS_IP)} or ${LAN_IP:-the LAN address}, user "$RDP_USER".
          SSH: ssh $USER@${TS_HOSTNAME:-$LAN_IP}
Rescue over SSH:  pinlock-reset (lift a PIN lockout)   pinlock-off (disable the PIN lock)
Change the PIN:   pinlock-set        Last attempts: pinlock-log
EOF
