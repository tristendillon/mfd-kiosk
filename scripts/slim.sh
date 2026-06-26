#!/usr/bin/env bash
set -euo pipefail

# Aggressive footprint trims for a small, low-RAM kiosk device.
# Compressed RAM swap (zram)
# Package systemd-zram-generator is installed by scripts/packages.sh.
install -d -m 755 /etc/systemd
install -m 644 ./files/zram/zram-generator.conf /etc/systemd/zram-generator.conf

# Cap journal disk usage
install -d -m 755 /etc/systemd/journald.conf.d
install -m 644 ./files/systemd/journald-kiosk.conf \
  /etc/systemd/journald.conf.d/00-kiosk.conf

for unit in \
  ModemManager.service \
  multipathd.service \
  apport.service \
  apport-autoreport.path \
  apport-forward.socket \
  networkd-dispatcher.service \
  open-iscsi.service \
  iscsid.socket \
  lxd-installer.socket \
  mdmonitor.service \
  pollinate.service \
  motd-news.timer \
  mdcheck_start.timer \
  mdcheck_continue.timer \
  mdmonitor-oneshot.timer \
  xfs_scrub_all.timer; do
  systemctl mask "$unit" 2>/dev/null || true
done

if [ -d /etc/cloud ]; then
  touch /etc/cloud/cloud-init.disabled
fi

DEBIAN_FRONTEND=noninteractive apt-get purge -y kdump-tools 2>/dev/null || true
update-grub 2>/dev/null || true
