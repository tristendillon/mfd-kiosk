{ config, pkgs, ... }:

# The per-device token is provisioned at install time (and
# re-settable over SSH) into a runtime file OUTSIDE the Nix store, so it never
# lands in git or a world-readable store path.
let
  cfg = config.mfd.kiosk;

  setToken = pkgs.writeShellApplication {
    name = "mfd-set-token";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd ];
    text = ''
      #!/usr/bin/env bash
      if [ "$(id -u)" -ne 0 ]; then
        echo "Run as root: sudo mfd-set-token" >&2
        exit 1
      fi

      # Per-device base URL is stamped by the install wizard to
      # ${cfg.stateDir}/base-url (outside the Nix store); fall back to the baked
      # default for raw-dd'd images that never went through the wizard.
      base="${cfg.baseUrl}"
      if [ -s "${cfg.stateDir}/base-url" ]; then
        file_base="$(head -n1 "${cfg.stateDir}/base-url")"
        if [ -n "$file_base" ]; then
          base="$file_base"
        fi
      fi

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

      # Normalise the token: strip a leading slash and any query string.
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
      # restart (not try-restart): also STARTS the browser when it was
      # condition-blocked by a missing token file.
      systemctl restart cage-tty1.service 2>/dev/null || true
    '';
  };
in
{
  environment.systemPackages = [ setToken ];

  # Ensure the directory exists; the token file itself is written at runtime by
  # mfd-set-token, never by Nix. The directory must exist anyway so the
  # mfd-kiosk-start path unit (browser.nix) can watch for the file appearing.
  systemd.tmpfiles.rules = [
    "d ${builtins.dirOf cfg.tokenFile} 0750 root ${cfg.kioskUser} -"
  ];

  # Unprovisioned kiosk: the screen is intentionally blank, so prompt for the
  # token as soon as the admin logs in interactively (console or SSH). Only for
  # interactive shells — scp/sftp/`ssh host cmd` never source this.
  programs.bash.interactiveShellInit = ''
    if [ -t 0 ] && [ "$(id -un)" = "${cfg.adminUser}" ] && [ ! -e ${cfg.tokenFile} ]; then
      echo
      echo "No dashboard token is configured on this kiosk."
      echo "Enter one now (Ctrl-C to skip; run 'sudo mfd-set-token' anytime)."
      sudo mfd-set-token || true
    fi
  '';
}
