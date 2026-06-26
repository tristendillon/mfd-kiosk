#!/usr/bin/env bash
set -euo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  lightdm \
  openbox \
  xorg \
  dbus-x11 \
  unclutter \
  chromium-browser \
  fonts-dejavu \
  fonts-liberation \
  x11-xserver-utils \
  curl \
  ca-certificates \
  git
