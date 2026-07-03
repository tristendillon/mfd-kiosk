{ config, lib, ... }:

# cage handles VT auto-login of the kiosk user, so no getty override is needed.
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
    # Optional baked recovery keys; per-device keys come from the install
    # wizard via sshd's extra AuthorizedKeysFile path (see ssh.nix).
    openssh.authorizedKeys.keys = cfg.adminKeys;
    # Password hash is per-device state written by the install wizard. If the
    # file is missing (raw-dd'd image), activation warns and locks the account.
    hashedPasswordFile = "${cfg.stateDir}/${cfg.adminUser}.hash";
  };

  security.sudo.wheelNeedsPassword = lib.mkDefault false;
}
