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

if [[ -z "${MFD_UNINSTALL_STAGED:-}" ]] && [[ -f "$SCRIPT_DIR/config.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/config.env"
fi

KIOSK_USER="${KIOSK_USER:-kiosk}"
INSTALL_DIR="${INSTALL_DIR:-/opt/mfd-kiosk}"

STAGED_PATH="/tmp/mfd-kiosk-uninstall.sh"

if [[ -z "${MFD_UNINSTALL_STAGED:-}" ]]; then
  cat <<EOF

This will COMPLETELY remove the MFD kiosk from this device:

  - systemd units:   mfd-browser-healthcheck.{service,timer},
                     mfd-daily-reboot.{service,timer}
  - autologin:       /etc/systemd/system/getty@tty1.service.d/override.conf
  - X config:        /etc/X11/Xwrapper.config, /etc/X11/xorg.conf.d/10-monitor.conf
  - ssh config:      /etc/ssh/sshd_config.d/99-mfd-kiosk.conf
  - firefox policy:  /etc/firefox/policies/policies.json
  - mozilla repo:    sources/key/pin + /etc/apt/preferences.d/no-snapd
  - zram/journald:   /etc/systemd/zram-generator.conf, journald cap drop-in
  - masked daemons:  ModemManager, multipathd (unmasked)
  - sleep targets:   unmasked (sleep/suspend/hibernate/hybrid-sleep)
  - token store:     /etc/mfd-kiosk
  - user:            $KIOSK_USER (and its home directory)
  - packages:        openbox, firefox-esr, xserver-xorg-*, fonts-dejavu-core,
                     systemd-zram-generator, etc.
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

echo "[uninstall] Stopping kiosk services."

systemctl disable --now mfd-browser-healthcheck.timer mfd-browser-healthcheck.service 2>/dev/null || true
systemctl disable --now mfd-daily-reboot.timer mfd-daily-reboot.service 2>/dev/null || true

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

echo "[uninstall] Restoring masked kiosk daemons."
systemctl unmask ModemManager.service multipathd.service 2>/dev/null || true

echo "[uninstall] Removing autologin and X session config."
rm -f /etc/systemd/system/getty@tty1.service.d/override.conf
rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
rm -f /etc/X11/Xwrapper.config
systemctl daemon-reload

echo "[uninstall] Removing Firefox policy, zram, and journald drop-ins."
rm -f /etc/firefox/policies/policies.json
rmdir /etc/firefox/policies /etc/firefox 2>/dev/null || true
rm -f /etc/systemd/zram-generator.conf
rm -f /etc/systemd/journald.conf.d/00-kiosk.conf

echo "[uninstall] Removing Mozilla apt repo and snapd pin."
rm -f /etc/apt/sources.list.d/mozilla.list \
      /etc/apt/keyrings/packages.mozilla.org.asc \
      /etc/apt/preferences.d/mozilla \
      /etc/apt/preferences.d/no-snapd

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
  firefox-esr \
  openbox \
  xserver-xorg-core \
  xserver-xorg-legacy \
  xserver-xorg-input-libinput \
  xinit \
  x11-xserver-utils \
  dbus-x11 \
  fonts-dejavu-core \
  systemd-zram-generator 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y 2>/dev/null || true

echo "[uninstall] Removing install directory: $INSTALL_DIR"
rm -rf "$INSTALL_DIR"

echo
echo "Uninstall complete. The MFD kiosk has been fully removed."
echo "SSH access (openssh-server) was preserved."

rm -f "$STAGED_PATH"
