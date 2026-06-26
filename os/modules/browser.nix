{ config, pkgs, lib, ... }:

# The heart of the rewrite. Replaces firefox.sh, session.sh, openbox.sh,
# files/openbox/autostart, power.sh, healthcheck.sh and files/x11/* — the entire
# X / openbox / startx / autostart-loop / DPMS stack collapses into one cage
# service running cog fullscreen.
let
  cfg = config.mfd.kiosk;

  # cog's URL carries the per-device token, which is NOT known at build time, so
  # we read it from the runtime token file and exec cog from a wrapper.
  launcher = pkgs.writeShellScript "mfd-kiosk-launch" ''
    set -eu

    if [ ! -r "${cfg.tokenFile}" ]; then
      echo "mfd-kiosk: ${cfg.tokenFile} missing/unreadable; run 'sudo mfd-set-token'" >&2
      sleep 30   # avoid a tight crash-loop while unprovisioned
      exit 1
    fi

    # shellcheck disable=SC1090
    . "${cfg.tokenFile}"

    if [ -z "''${KIOSK_URL:-}" ]; then
      echo "mfd-kiosk: KIOSK_URL not set in ${cfg.tokenFile}" >&2
      sleep 30
      exit 1
    fi

    exec ${pkgs.cog}/bin/cog ${lib.escapeShellArgs cfg.extraCogArgs} "$KIOSK_URL"
  '';
in
{
  # cage = single-app Wayland kiosk compositor; auto-logs in the kiosk user and
  # renders cog fullscreen on the primary display.
  services.cage = {
    enable = true;
    user = cfg.kioskUser;
    program = launcher;
  };

  # Crash -> restart (replaces the old 2-minute healthcheck poll). NOTE: confirm
  # the unit name on first boot with `systemctl status cage-tty1`; adjust if the
  # cage module names it differently on your nixpkgs pin.
  systemd.services."cage-tty1".serviceConfig = {
    Restart = lib.mkForce "always";
    RestartSec = "2s";
  };

  # GPU / WebGL for Google Maps — mesa covers Intel i915 and AMD amdgpu, so one
  # image accelerates on both board families.
  hardware.graphics.enable = true;

  # Display-only appliance: never sleep, and (by running no idle daemon) never
  # blank. This replaces the X DPMS config in power.sh.
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
}
