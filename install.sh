#!/usr/bin/env bash
set -euo pipefail

ORIGINAL_ARGS=("$@")

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR"

if [[ "$EUID" -ne 0 ]]; then
  echo "Run with sudo: sudo ./install.sh"
  exit 1
fi

if [[ -f "$SCRIPT_DIR/config.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/config.env"
fi

KIOSK_USER="${KIOSK_USER:-kiosk}"
INSTALL_DIR="${INSTALL_DIR:-/opt/mfd-kiosk}"

detect_admin_user() {
  if [[ -n "${KIOSK_ADMIN_USER:-}" ]] && id "$KIOSK_ADMIN_USER" >/dev/null 2>&1; then
    echo "$KIOSK_ADMIN_USER"
    return 0
  fi

  if [[ -n "${SUDO_USER:-}" ]] \
    && [[ "$SUDO_USER" != "root" ]] \
    && [[ "$SUDO_USER" != "$KIOSK_USER" ]] \
    && id "$SUDO_USER" >/dev/null 2>&1; then
    echo "$SUDO_USER"
    return 0
  fi

  local sudo_members
  sudo_members="$(getent group sudo | awk -F: '{print $4}' | tr ',' ' ')"

  for user in $sudo_members; do
    if [[ "$user" != "root" ]] && [[ "$user" != "$KIOSK_USER" ]] && id "$user" >/dev/null 2>&1; then
      echo "$user"
      return 0
    fi
  done

  echo "Could not detect an admin user." >&2
  echo "Set KIOSK_ADMIN_USER=\"technician\" in config.env and rerun." >&2
  return 1
}

KIOSK_ADMIN_USER="$(detect_admin_user)"
export KIOSK_ADMIN_USER
export KIOSK_USER
export INSTALL_DIR

bootstrap_to_opt() {
  if [[ "$SCRIPT_DIR" == "$INSTALL_DIR" ]]; then
    return 0
  fi

  echo "[bootstrap] Admin user: $KIOSK_ADMIN_USER"
  echo "[bootstrap] Moving installer to $INSTALL_DIR"

  mkdir -p "$INSTALL_DIR"

  # Copy repo contents into /opt/mfd-kiosk.
  # This preserves .git if the repo was cloned with Git.
  cp -a "$SCRIPT_DIR"/. "$INSTALL_DIR"/

  chown -R "$KIOSK_ADMIN_USER:$KIOSK_ADMIN_USER" "$INSTALL_DIR"

  echo "[bootstrap] Re-running installer from $INSTALL_DIR"

  export MFD_KIOSK_ORIGINAL_DIR="$SCRIPT_DIR"
  exec "$INSTALL_DIR/install.sh" "${ORIGINAL_ARGS[@]}"
}

cleanup_original_dir() {
  local original_dir="${MFD_KIOSK_ORIGINAL_DIR:-}"

  if [[ -z "$original_dir" ]]; then
    return 0
  fi

  if [[ "$original_dir" == "$INSTALL_DIR" ]]; then
    return 0
  fi

  if [[ ! -d "$original_dir" ]]; then
    return 0
  fi

  case "$original_dir" in
    /root/*|/home/*|/tmp/*)
      if [[ -f "$original_dir/install.sh" ]] && [[ -f "$original_dir/config.env" ]]; then
        echo "[cleanup] Removing old installer copy at $original_dir"
        rm -rf "$original_dir"
      fi
      ;;
    *)
      echo "[cleanup] Not removing original directory outside /root, /home, or /tmp: $original_dir"
      ;;
  esac
}

bootstrap_to_opt

cd "$INSTALL_DIR"

source ./config.env

export KIOSK_ADMIN_USER
export KIOSK_USER
export KIOSK_URL
export REBOOT_TIME
export BROWSER_BIN
export INSTALL_DIR

echo "[install] Running from: $INSTALL_DIR"
echo "[install] Admin user: $KIOSK_ADMIN_USER"
echo "[install] Kiosk user: $KIOSK_USER"

./scripts/packages.sh
./scripts/users.sh
./scripts/ssh.sh
./scripts/token.sh
./scripts/lightdm.sh
./scripts/openbox.sh
./scripts/power.sh
./scripts/timers.sh
./scripts/healthcheck.sh

systemctl daemon-reload
systemctl enable lightdm
systemctl enable mfd-daily-reboot.timer
systemctl enable mfd-browser-healthcheck.timer

chown -R "$KIOSK_ADMIN_USER:$KIOSK_ADMIN_USER" "$INSTALL_DIR"

cleanup_original_dir

echo
echo "Install complete."
echo "Installer location: $INSTALL_DIR"
echo "Owner: $KIOSK_ADMIN_USER"
echo
echo "Reboot with:"
echo "  sudo reboot"
