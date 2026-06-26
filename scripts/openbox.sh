#!/usr/bin/env bash
set -euo pipefail

install -d -o "$KIOSK_USER" -g "$KIOSK_USER" "/home/$KIOSK_USER/.config/openbox"

envsubst < ./files/openbox/autostart \
  > "/home/$KIOSK_USER/.config/openbox/autostart"

chmod +x "/home/$KIOSK_USER/.config/openbox/autostart"
chown -R "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/.config"
