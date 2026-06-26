{ config, ... }:

# Replaces ssh.sh. Admin-only, key-only SSH; the kiosk user is display-only and
# must never be reachable; root login disabled.
let
  cfg = config.mfd.kiosk;
in
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      DenyUsers = [ cfg.kioskUser ];
    };
  };
}
