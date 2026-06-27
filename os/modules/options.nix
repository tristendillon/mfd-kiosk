{ lib, ... }:

{
  options.mfd.kiosk = {
    baseUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://mfd.alertdashboard.com";
      description = ''
        Base dashboard URL. The per-device token is appended at runtime to form
        the full kiosk URL; the token itself is never stored in the Nix store.
      '';
    };

    rebootTime = lib.mkOption {
      type = lib.types.str;
      default = "04:00";
      description = "Daily reboot time, HH:MM (systemd OnCalendar).";
    };

    kioskUser = lib.mkOption {
      type = lib.types.str;
      default = "kiosk";
      description = "Display-only user that cage auto-logs in.";
    };

    adminUser = lib.mkOption {
      type = lib.types.str;
      default = "technician";
      description = "Administrator user reachable over SSH (wheel).";
    };

    adminKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Authorized SSH public keys for the admin user.";
    };

    diskDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/sda";
      description = "Target install disk (disko). Override per board at install.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/mfd-kiosk/kiosk.env";
      description = "Runtime file holding KIOSK_URL; outside the Nix store.";
    };

    extraFirefoxArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--width=1920" "--height=1080" ];
      description = ''
        Extra arguments spliced into the firefox-esr command line before the URL.
        The launcher already passes --profile and --kiosk.
      '';
    };
  };
}
