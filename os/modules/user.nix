{ config, lib, ... }:

# Replaces users.sh and the autologin half of session.sh. cage handles VT
# auto-login of the kiosk user, so no getty override is needed.
let
  cfg = config.mfd.kiosk;
in
{
  users.mutableUsers = false;

  # Dedicated group so the token file (root:kiosk 0640, see secrets.nix) is
  # readable by the kiosk user but not world. isNormalUser would otherwise put
  # the user in the shared `users` group, and `kiosk` would not exist at all —
  # mfd-set-token's `install -g kiosk` then fails with "invalid group 'kiosk'".
  users.groups.${cfg.kioskUser} = { };

  users.users.${cfg.kioskUser} = {
    isNormalUser = true;
    group = cfg.kioskUser;
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
