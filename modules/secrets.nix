{ config, pkgs, lib, ... }:

# Replaces token.sh. The per-device token is provisioned at install time (and
# re-settable over SSH) into a runtime file OUTSIDE the Nix store, so it never
# lands in git or a world-readable store path.
let
  cfg = config.mfd.kiosk;

  setToken = pkgs.writeShellApplication {
    name = "mfd-set-token";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "Run as root: sudo mfd-set-token" >&2
        exit 1
      fi

      base="${cfg.baseUrl}"
      printf 'Dashboard token (input hidden): '
      stty -echo 2>/dev/null || true
      read -r token
      stty echo 2>/dev/null || true
      printf '\n'

      if [ -z "$token" ]; then
        echo "Token cannot be empty." >&2
        exit 1
      fi
      case "$token" in
        *[[:space:]]*) echo "Token cannot contain whitespace." >&2; exit 1 ;;
      esac

      # Mirror token.sh normalisation: strip a leading slash and any query string.
      token="''${token#/}"
      token="''${token%%\?*}"

      url="''${base%/}/$token"
      dir="$(dirname "${cfg.tokenFile}")"

      install -d -m 0750 -o root -g "${cfg.kioskUser}" "$dir"
      umask 027
      printf "KIOSK_URL='%s'\n" "$url" > "${cfg.tokenFile}"
      chown "root:${cfg.kioskUser}" "${cfg.tokenFile}"
      chmod 0640 "${cfg.tokenFile}"

      echo "Saved ${cfg.tokenFile} (not in the Nix store or git)."
      systemctl try-restart cage-tty1.service 2>/dev/null || true
    '';
  };
in
{
  environment.systemPackages = [ setToken ];

  # Ensure the directory exists; the token file itself is written at runtime by
  # mfd-set-token, never by Nix.
  systemd.tmpfiles.rules = [
    "d ${builtins.dirOf cfg.tokenFile} 0750 root ${cfg.kioskUser} -"
  ];
}
