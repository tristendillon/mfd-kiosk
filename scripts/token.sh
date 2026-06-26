#!/usr/bin/env bash
set -euo pipefail

TOKEN_DIR="/etc/mfd-kiosk"
TOKEN_FILE="$TOKEN_DIR/kiosk.env"

echo
echo "Enter the private dashboard token for this kiosk."
echo "Input will be hidden."
echo

read -rsp "Dashboard token: " DASHBOARD_TOKEN
echo

if [[ -z "$DASHBOARD_TOKEN" ]]; then
  echo "Dashboard token cannot be empty."
  exit 1
fi

if [[ "$DASHBOARD_TOKEN" =~ [[:space:]] ]]; then
  echo "Dashboard token cannot contain whitespace."
  exit 1
fi

DASHBOARD_TOKEN="${DASHBOARD_TOKEN#/}"
DASHBOARD_TOKEN="${DASHBOARD_TOKEN%%\?*}"

KIOSK_URL="${KIOSK_BASE_URL%/}/${DASHBOARD_TOKEN}?${KIOSK_QUERY}"

install -d -m 750 -o root -g "$KIOSK_USER" "$TOKEN_DIR"

cat >"$TOKEN_FILE" <<EOF
KIOSK_URL='$KIOSK_URL'
EOF

chown root:"$KIOSK_USER" "$TOKEN_FILE"
chmod 640 "$TOKEN_FILE"

export KIOSK_URL

echo "Dashboard token saved locally to $TOKEN_FILE"
echo "Token was not written to the Git repo."
