#!/usr/bin/env bash
set -euo pipefail

envsubst < ./files/systemd/mfd-browser-healthcheck.service \
  > /etc/systemd/system/mfd-browser-healthcheck.service

cp ./files/systemd/mfd-browser-healthcheck.timer \
  /etc/systemd/system/mfd-browser-healthcheck.timer
