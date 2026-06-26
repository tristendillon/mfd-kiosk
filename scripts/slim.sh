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

# Mask daemons a display-only kiosk never needs
# Networking and unattended-upgrades are intentionally left running.
for unit in ModemManager.service multipathd.service; do
  systemctl mask "$unit" 2>/dev/null || true
done
