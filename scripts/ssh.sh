#!/usr/bin/env bash
set -euo pipefail

SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSHD_CONFIG_FILE="$SSHD_CONFIG_DIR/99-mfd-kiosk.conf"

mkdir -p "$SSHD_CONFIG_DIR"

cat >"$SSHD_CONFIG_FILE" <<EOF
# Managed by mfd-kiosk installer.
# The kiosk user is display-only and must not be reachable over SSH.

DenyUsers $KIOSK_USER
PermitRootLogin no
EOF

chmod 644 "$SSHD_CONFIG_FILE"
chown root:root "$SSHD_CONFIG_FILE"

sshd -t

systemctl reload ssh 2>/dev/null || systemctl restart ssh
