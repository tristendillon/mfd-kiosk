{ config, ... }:

# Declarative daily reboot; browser crash-restart lives in browser.nix
# (Restart=always).
let
  cfg = config.mfd.kiosk;
in
{
  systemd.services.mfd-daily-reboot = {
    description = "Daily reboot for MFD kiosk";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/systemctl reboot";
    };
  };

  systemd.timers.mfd-daily-reboot = {
    description = "Run daily MFD kiosk reboot";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* ${cfg.rebootTime}:00";
      Persistent = true;
    };
  };
}
