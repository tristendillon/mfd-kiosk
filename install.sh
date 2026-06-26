#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ "$EUID" -ne 0 ]]; then
  echo "Run with sudo: sudo ./install.sh"
  exit 1
fi

source ./config.env

export KIOSK_USER
export KIOSK_URL
export REBOOT_TIME
export BROWSER_BIN

./scripts/packages.sh
./scripts/users.sh
./scripts/lightdm.sh
./scripts/openbox.sh
./scripts/power.sh
./scripts/timers.sh
./scripts/healthcheck.sh

systemctl daemon-reload
systemctl enable lightdm
systemctl enable mfd-daily-reboot.timer
systemctl enable mfd-browser-healthcheck.timer

echo "Install complete. Reboot with: sudo reboot"
