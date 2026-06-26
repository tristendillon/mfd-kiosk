#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ "$EUID" -ne 0 ]]; then
  echo "Run with sudo: sudo ./uninstall.sh"
  exit 1
fi

ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Pull KIOSK_USER / INSTALL_DIR from the installed config if available, so we
# remove exactly what was installed. Fall back to the installer defaults.
if [[ -z "${MFD_UNINSTALL_STAGED:-}" ]] && [[ -f "$SCRIPT_DIR/config.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/config.env"
fi

KIOSK_USER="${KIOSK_USER:-kiosk}"
INSTALL_DIR="${INSTALL_DIR:-/opt/mfd-kiosk}"

STAGED_PATH="/tmp/mfd-kiosk-uninstall.sh"

# ---------------------------------------------------------------------------
# Stage 1: confirm, then relocate to /tmp so we can delete $INSTALL_DIR safely.
# ---------------------------------------------------------------------------
if [[ -z "${MFD_UNINSTALL_STAGED:-}" ]]; then
  cat <<EOF

This will COMPLETELY remove the MFD kiosk from this device:

  - systemd units:   mfd-browser-healthcheck.{service,timer},
                     mfd-daily-reboot.{service,timer}
  - lightdm config:  /etc/lightdm/lightdm.conf.d/50-mfd-kiosk.conf (and disables lightdm)
  - ssh config:      /etc/ssh/sshd_config.d/99-mfd-kiosk.conf
  - xorg config:     /etc/X11/xorg.conf.d/10-monitor.conf
  - sleep targets:   unmasked (sleep/suspend/hibernate/hybrid-sleep)
  - token store:     /etc/mfd-kiosk
  - user:            $KIOSK_USER (and its home directory)
  - packages:        lightdm, openbox, unclutter, chromium-browser, xorg, etc.
                     (openssh-server, git, curl, ca-certificates are KEPT)
  - install dir:     $INSTALL_DIR

EOF

  if [[ "$ASSUME_YES" -ne 1 ]]; then
    read -rp "Type 'yes' to proceed: " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
      echo "Aborted."
      exit 1
    fi
  fi

  cp -f "${BASH_SOURCE[0]}" "$STAGED_PATH"
  chmod +x "$STAGED_PATH"

  echo "[uninstall] Re-running from $STAGED_PATH so $INSTALL_DIR can be removed."
  export MFD_UNINSTALL_STAGED=1
  export KIOSK_USER
  export INSTALL_DIR
  exec "$STAGED_PATH" --yes
fi

# ---------------------------------------------------------------------------
# Stage 2: running from /tmp. Tear everything down.
# ---------------------------------------------------------------------------
echo "[uninstall] Stopping kiosk services."

# Disable the healthcheck first so it cannot restart lightdm mid-teardown.
systemctl disable --now mfd-browser-healthcheck.timer mfd-browser-healthcheck.service 2>/dev/null || true
systemctl disable --now mfd-daily-reboot.timer mfd-daily-reboot.service 2>/dev/null || true
systemctl disable --now lightdm 2>/dev/null || true

echo "[uninstall] Removing systemd unit files."
rm -f /etc/systemd/system/mfd-browser-healthcheck.service \
      /etc/systemd/system/mfd-browser-healthcheck.timer \
      /etc/systemd/system/mfd-daily-reboot.service \
      /etc/systemd/system/mfd-daily-reboot.timer
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

echo "[uninstall] Restoring power management."
systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
rm -f /etc/X11/xorg.conf.d/10-monitor.conf

echo "[uninstall] Removing config drop-ins."
rm -f /etc/lightdm/lightdm.conf.d/50-mfd-kiosk.conf

if [[ -f /etc/ssh/sshd_config.d/99-mfd-kiosk.conf ]]; then
  rm -f /etc/ssh/sshd_config.d/99-mfd-kiosk.conf
  systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || true
fi

rm -rf /etc/mfd-kiosk

echo "[uninstall] Removing the $KIOSK_USER user."
if id "$KIOSK_USER" >/dev/null 2>&1; then
  loginctl terminate-user "$KIOSK_USER" 2>/dev/null || true
  pkill -KILL -u "$KIOSK_USER" 2>/dev/null || true
  deluser --remove-home "$KIOSK_USER" 2>/dev/null || userdel -r "$KIOSK_USER" 2>/dev/null || true
fi

echo "[uninstall] Purging kiosk packages (openssh-server/git/curl are kept)."
DEBIAN_FRONTEND=noninteractive apt-get purge -y \
  lightdm \
  lightdm-gtk-greeter \
  openbox \
  unclutter \
  chromium-browser \
  xorg \
  x11-xserver-utils \
  dbus-x11 \
  fonts-dejavu \
  fonts-liberation 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y 2>/dev/null || true

echo "[uninstall] Removing install directory: $INSTALL_DIR"
rm -rf "$INSTALL_DIR"

echo
echo "Uninstall complete. The MFD kiosk has been fully removed."
echo "SSH access (openssh-server) was preserved."

# Clean up this staged copy. The script is already loaded into memory, so
# removing the file on disk is safe.
rm -f "$STAGED_PATH"
