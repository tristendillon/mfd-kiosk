#!/usr/bin/env bash
set -euo pipefail

install -d -m 0755 /etc/apt/keyrings

curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
  -o /etc/apt/keyrings/packages.mozilla.org.asc

cat >/etc/apt/sources.list.d/mozilla.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main
EOF

cat >/etc/apt/preferences.d/mozilla <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

apt-get update

# Guard: refuse to fall back to the Snap browser.
# The candidate for firefox-esr MUST come from the Mozilla repo. If it does not
# (repo unreachable, key/pin wrong, etc.) we stop instead of silently pulling
# the Snap.
if ! apt-cache policy firefox-esr | grep -q 'packages.mozilla.org'; then
  echo "ERROR: firefox-esr is not available from the Mozilla apt repo." >&2
  echo "Refusing to fall back to the Snap browser. Aborting." >&2
  exit 1
fi

# Trimmed kiosk stack. --no-install-recommends keeps the footprint minimal.
#
# Notes:
#   - xserver-xorg-core ships the `modesetting` (KMS) driver, which covers
#     Intel N100 / typical thin clients. If a specific device needs a discrete
#     driver, add the matching xserver-xorg-video-* package below.
#   - No lightdm/greeter: the session is started by tty autologin + startx
#     (see scripts/session.sh).
#   - No unclutter: the cursor is hidden via `startx -- -nocursor`.
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  openssh-server \
  xserver-xorg-core \
  xserver-xorg-legacy \
  xserver-xorg-input-libinput \
  xinit \
  openbox \
  x11-xserver-utils \
  dbus-x11 \
  fonts-dejavu-core \
  firefox-esr \
  systemd-zram-generator \
  curl \
  ca-certificates \
  git

# Purge and block snapd. With a .deb Firefox there is nothing left that needs
# Snap, so we reclaim the daemon, its squashfs loop mounts, and the disk.
systemctl stop snapd.socket snapd.service 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get purge -y snapd 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y 2>/dev/null || true
rm -rf /var/cache/snapd /root/snap /home/*/snap 2>/dev/null || true

cat >/etc/apt/preferences.d/no-snapd <<'EOF'
Package: snapd
Pin: release *
Pin-Priority: -1
EOF

# Reclaim disk used during install.
apt-get clean
journalctl --vacuum-size=50M 2>/dev/null || true
