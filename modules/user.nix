{ config, lib, ... }:

# Replaces users.sh and the autologin half of session.sh. cage handles VT
# auto-login of the kiosk user, so no getty override is needed.
let
  cfg = config.mfd.kiosk;
in
{
  users.mutableUsers = false;

  users.users.${cfg.kioskUser} = {
    isNormalUser = true;
    description = "MFD display-only kiosk user";
    hashedPassword = "!"; # locked: no password, not reachable via SSH (ssh.nix)
  };

  users.users.${cfg.adminUser} = {
    isNormalUser = true;
    description = "MFD kiosk administrator";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = cfg.adminKeys;
    hashedPassword = "!"; # key-only login; sudo is passwordless below
  };

  # Admin logs in by SSH key only, so there is no password to type for sudo.
  security.sudo.wheelNeedsPassword = lib.mkDefault false;

  assertions = [{
    assertion = cfg.adminKeys != [ ];
    message = "mfd.kiosk.adminKeys is empty — set at least one SSH key or you will be locked out.";
  }];
}
