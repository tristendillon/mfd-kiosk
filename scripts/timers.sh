#!/usr/bin/env bash
set -euo pipefail

envsubst < ./files/systemd/mfd-daily-reboot.service \
  > /etc/systemd/system/mfd-daily-reboot.service

envsubst < ./files/systemd/mfd-daily-reboot.timer \
  > /etc/systemd/system/mfd-daily-reboot.timer
