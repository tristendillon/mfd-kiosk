#!/usr/bin/env bash
set -euo pipefail

if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$KIOSK_USER"
fi
