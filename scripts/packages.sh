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

# Fail loudly if ANY configured repo (especially Mozilla) fails to refresh.
# Without Error-Mode=any a transient fetch/verify failure of the Mozilla
# InRelease only prints a warning, apt-get still exits 0, and we limp on to the
# guard below with a misleading "package not available" message. Retry a few
# times to ride out transient network blips during provisioning.
for attempt in 1 2 3; do
  if apt-get update -o APT::Update::Error-Mode=any; then
    break
  fi
  if [ "$attempt" = 3 ]; then
    echo "ERROR: apt-get update failed after 3 attempts (see warnings above)." >&2
    exit 1
  fi
  echo "apt-get update failed (attempt $attempt/3); retrying in 5s..." >&2
  sleep 5
done

# Guard: refuse to fall back to the Snap browser.
# Belt-and-suspenders after the hardened update above: the candidate for
# firefox-esr MUST come from the Mozilla repo. If it does not (pin wrong, repo
# not indexed) we stop instead of silently pulling the Snap.
#
# Capture into a variable and grep a here-string rather than
# `apt-cache policy ... | grep -q`. With `set -o pipefail`, grep -q exits on
# its first match and closes the pipe; apt-cache then dies of SIGPIPE (141)
# and pipefail reports the whole pipeline as failed *even though the match
# succeeded* — which inverted this guard and aborted on a perfectly good repo.
policy="$(apt-cache policy firefox-esr)"
if ! grep -q 'packages.mozilla.org' <<<"$policy"; then
  echo "ERROR: firefox-esr has no candidate from packages.mozilla.org." >&2
  echo "The Mozilla apt repo isn't indexed (key/pin/network issue)." >&2
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

# Drop firmware blobs for hardware this board does not have — hardware-aware so
# the same image is safe on Intel *and* AMD kiosks. Rather than assume a vendor,
# read the PCI vendor IDs actually present and only purge firmware for silicon
# that is absent (e.g. keep linux-firmware-amd-graphics on an AMD board, keep a
# Wi-Fi firmware package if that radio is present). Intel/generic/SOF firmware
# is never targeted here. Reads /sys directly, so no pciutils dependency.
present_vendors="$(cat /sys/bus/pci/devices/*/vendor 2>/dev/null | tr 'A-F' 'a-f' | sort -u)"

if [ -n "$present_vendors" ]; then
  # purge_fw_unless_present <package> <pci-vendor-id>...
  # Purge the firmware package only if NONE of the given PCI vendor IDs is
  # present. grep reads a here-string (no pipe) so pipefail/SIGPIPE can't bite.
  purge_fw_unless_present() {
    local pkg="$1"; shift
    local id
    for id in "$@"; do
      if grep -qix "0x${id}" <<<"$present_vendors"; then
        return 0   # matching hardware present -> keep the firmware
      fi
    done
    DEBIAN_FRONTEND=noninteractive apt-get purge -y "$pkg" 2>/dev/null || true
  }

  purge_fw_unless_present linux-firmware-nvidia-graphics    10de
  purge_fw_unless_present linux-firmware-amd-graphics       1002
  purge_fw_unless_present linux-firmware-qualcomm-misc      17cb 168c
  purge_fw_unless_present linux-firmware-qualcomm-wireless  17cb 168c
  purge_fw_unless_present linux-firmware-mediatek           14c3 14c4 0e8d
  purge_fw_unless_present linux-firmware-mellanox-spectrum  15b3
  purge_fw_unless_present linux-firmware-marvell-prestera   11ab 1b4b
else
  # Fail safe: if we cannot enumerate PCI vendors, keep all firmware.
  echo "WARN: could not read PCI vendor IDs; skipping firmware trim." >&2
fi

# Reclaim disk used during install.
apt-get clean
journalctl --vacuum-size=50M 2>/dev/null || true
