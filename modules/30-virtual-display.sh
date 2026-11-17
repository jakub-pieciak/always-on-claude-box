# shellcheck shell=bash
# Virtual 1920x1080 monitor, so GNOME (and Remote Desktop) work with nothing plugged in.
# The kernel treats the HDMI port as connected (video=...e) and reads a monitor description
# (EDID) from a file (drm.edid_firmware). A real monitor plugged in later still works.

module_virtual_display() {
  step "Virtual display (headless operation)"
  command -v update-grub >/dev/null || { warn "No GRUB (update-grub missing); skipping the virtual display."; return; }

  local conn="${VD_CONNECTOR:-}" s
  if [[ -z "$conn" ]]; then
    for s in /sys/class/drm/card*-HDMI-A-*; do [[ -e "$s" ]] || continue; conn="${s##*/card[0-9]-}"; break; done
  fi
  [[ -n "$conn" ]] || { warn "No HDMI connector found; skipping. Available: $(ls /sys/class/drm | grep -- - | tr '\n' ' ')"; return; }
  info "Connector: $conn"

  local name=virtual-1080p75.bin path=/usr/lib/firmware/edid/virtual-1080p75.bin
  # 128-byte EDID 1.3 "Virtual 1080p": CVT-RB 1920x1080 @ 74.97 Hz preferred, 1920x1080 @ 60 Hz listed.
  base64 -d <<'EOF' | put "$path" 644 root
AP///////wAx2AEAAAAAAAEkAQOANB14Cu6Ro1RMmSYPUFQhCADRz9HAAQEBAQEBAQEBAQEBKkSAoHA4J0AwIDUACSUhAAAaAAAA/QA4TB5VEgAKICAgICAgAAAA/ABWaXJ0dWFsIDEwODBwAAAAEAAAAAAAAAAAAAAAAAAAAD8=
EOF

  if command -v dracut >/dev/null; then
    echo "install_items+=\" $path \"" | put /etc/dracut.conf.d/99-virtual-display.conf 644 root
  else
    put /etc/initramfs-tools/hooks/virtual-display-edid 755 root <<HOOK
#!/bin/sh
PREREQ=""
prereqs() { echo "\$PREREQ"; }
case "\$1" in prereqs) prereqs; exit 0;; esac
mkdir -p "\${DESTDIR}/usr/lib/firmware/edid"
cp "$path" "\${DESTDIR}/usr/lib/firmware/edid/"
HOOK
  fi

  put /etc/default/grub.d/99-virtual-display.cfg 644 root <<CFG
# Virtual monitor (always-on-claude-box): keep $conn on with a 1920x1080@75 EDID
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT drm.edid_firmware=$conn:edid/$name video=$conn:1920x1080@75e"
CFG
  NEED_INITRAMFS=true; NEED_GRUB=true
}
