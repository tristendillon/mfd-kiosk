{ lib, ... }:

{
  options.mfd.kiosk = {
    baseUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://mfdalertdashboard.com";
      description = ''
        DEFAULT base dashboard URL offered by the install wizard. The effective
        per-device value lives in ''${stateDir}/base-url (written by the wizard,
        outside the Nix store) and is read by mfd-set-token when building the
        full kiosk URL; this baked value is only the fallback. The per-device
        token is appended at runtime; the token itself is never stored in the
        Nix store.
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
      description = ''
        Optional baked-in SSH public keys for the admin user (fleet-wide
        recovery keys). Per-device keys are collected by the install wizard and
        written to ''${stateDir}/authorized_keys/ on the target disk instead.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mfd";
      description = ''
        Directory holding per-device state written by the install wizard
        (hostname, admin password hash, per-device SSH keys); outside the Nix
        store so one image serves every device. See identity.nix.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/mfd-kiosk/kiosk.env";
      description = "Runtime file holding KIOSK_URL; outside the Nix store.";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Diagnostic build toggle for bring-up on new/unsupported boards (e.g. the
        Cherry Trail Intel Compute Stick). When true: the boot is un-quieted
        (loglevel=7, verbose systemd status) and an autologin technician shell is
        placed on tty1 — the screen you're already looking at — so you can read
        the boot and get a shell WITHOUT a working VT-switch, USB keyboard, or a
        dashboard token. Leave false for production images. See modules/debug.nix.
      '';
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
