#!/usr/bin/env bash
set -euo pipefail

KIOSK_HOME="/home/$KIOSK_USER"

install -d -m 755 /etc/systemd/system/getty@tty1.service.d

cat >/etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

install -m 644 ./files/x11/Xwrapper.config /etc/X11/Xwrapper.config

cat >"$KIOSK_HOME/.bash_profile" <<'EOF'
# Managed by mfd-kiosk installer.
# Start the kiosk X session automatically on tty1, nowhere else.
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx -- -nocursor
fi
EOF

cat >"$KIOSK_HOME/.xinitrc" <<'EOF'
#!/bin/sh
# Managed by mfd-kiosk installer.
set -a
. /etc/mfd-kiosk/kiosk.env
set +a

xset -dpms
xset s off
xset s noblank

exec openbox-session
EOF
chmod +x "$KIOSK_HOME/.xinitrc"

chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.bash_profile" "$KIOSK_HOME/.xinitrc"
