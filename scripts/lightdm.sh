#!/usr/bin/env bash
set -euo pipefail

mkdir -p /etc/lightdm/lightdm.conf.d

envsubst < ./files/lightdm/50-mfd-kiosk.conf \
  > /etc/lightdm/lightdm.conf.d/50-mfd-kiosk.conf
