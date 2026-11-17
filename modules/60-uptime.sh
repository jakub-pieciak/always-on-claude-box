# shellcheck shell=bash
# Unattended operation: daily reboot, health checks every 5 min, auto-reboot after a kernel
# panic, hardware watchdog for full freezes.

module_uptime() {
  local files="$REPO_DIR/files/bin"

  step "Daily reboot at $REBOOT_TIME"
  put /usr/local/sbin/daily-reboot 755 root < "$files/daily-reboot"
  put /etc/systemd/system/daily-reboot.service 644 root <<'U'
[Unit]
Description=Scheduled daily reboot
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/daily-reboot
U
  put /etc/systemd/system/daily-reboot.timer 644 root <<U
[Unit]
Description=Reboot every day at $REBOOT_TIME
[Timer]
OnCalendar=*-*-* $REBOOT_TIME:00
# no catch-up reboot if the box was off at that time
Persistent=false
[Install]
WantedBy=timers.target
U

  step "Health checks every 5 minutes"
  info "system: network (restart NetworkManager, reboot after ~30 min offline, max once per 6 h),"
  info "        GDM, Tailscale, disk >90 % cleanup, CPU >=90 °C and low-RAM warnings"
  info "user:   Remote Desktop service, Chrome and Claude Desktop are restarted if they stop"
  put /usr/local/sbin/keepalive-system 755 root < "$files/keepalive-system"
  put "$HOME/.local/bin/keepalive-user" 755 < "$files/keepalive-user"
  put /etc/systemd/system/keepalive-system.service 644 root <<'U'
[Unit]
Description=Keepalive: network, GDM, Tailscale, disk, temperature
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/keepalive-system
U
  put /etc/systemd/system/keepalive-system.timer 644 root <<'U'
[Unit]
Description=Run keepalive-system every 5 minutes
[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
U
  put "$HOME/.config/systemd/user/keepalive-user.service" 644 <<'U'
[Unit]
Description=Keepalive: Remote Desktop, Chrome, Claude Desktop
[Service]
Type=oneshot
ExecStart=%h/.local/bin/keepalive-user
U
  put "$HOME/.config/systemd/user/keepalive-user.timer" 644 <<'U'
[Unit]
Description=Run keepalive-user every 5 minutes
[Timer]
OnActiveSec=5min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
U

  step "Reboot automatically after a kernel panic or lockup"
  printf 'kernel.panic = 10\nkernel.panic_on_oops = 1\nkernel.softlockup_panic = 1\n' \
    | put /etc/sysctl.d/90-keepalive.conf 644 root
  run sudo sysctl -q --system

  step "Hardware watchdog"
  # Intel TCO watchdog. Ubuntu deny-lists iTCO_wdt, so modules-load.d does not load it; a small
  # early-boot unit loads it by name and makes systemd (PID 1) pick it up.
  # RebootWatchdogSec=off is deliberate: a watchdog left running across a reboot made one
  # Chromebox hang mid-boot (black screen, no network) or hard-reset ~9 min after the reboot.
  if modinfo iTCO_wdt >/dev/null 2>&1 && { [[ -e /dev/watchdog0 ]] || run sudo modprobe iTCO_wdt 2>/dev/null; } \
     && { [[ "${DRY_RUN:-false}" == true ]] || [[ -e /dev/watchdog0 ]]; }; then
    put /etc/systemd/system/watchdog-load.service 644 root <<U
[Unit]
Description=Load the Intel hardware watchdog (iTCO_wdt) and let systemd arm it
DefaultDependencies=no
After=systemd-modules-load.service
Before=sysinit.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$(command -v modprobe) iTCO_wdt
ExecStartPost=/bin/sh -c 'sleep 1; [ "\$(cat /sys/class/watchdog/watchdog0/state 2>/dev/null)" = active ] || systemctl daemon-reexec'

[Install]
WantedBy=sysinit.target
U
    printf '[Manager]\nRuntimeWatchdogSec=60\n# off on purpose, see README\nRebootWatchdogSec=off\n' \
      | put /etc/systemd/system.conf.d/90-watchdog.conf 644 root
    WATCHDOG=true
    ok "Intel watchdog found: a full freeze longer than 60 s triggers a hardware reset."
  else
    WATCHDOG=false
    warn "No Intel TCO watchdog on this machine; skipping (kernel-panic reboot still applies)."
  fi

  step "Enabling timers"
  run sudo systemctl daemon-reload
  run sudo systemctl enable --now daily-reboot.timer keepalive-system.timer
  $WATCHDOG && run sudo systemctl enable watchdog-load.service
  run systemctl --user daemon-reload
  run systemctl --user enable --now keepalive-user.timer
}
