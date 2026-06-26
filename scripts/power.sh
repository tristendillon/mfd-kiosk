#!/usr/bin/env bash
set -euo pipefail

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target || true

mkdir -p /etc/X11/xorg.conf.d

cat >/etc/X11/xorg.conf.d/10-monitor.conf <<'EOF'
Section "ServerFlags"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
EndSection
EOF
