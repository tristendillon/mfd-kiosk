{ config, ... }:

# Replaces ssh.sh. Admin-only SSH: password (set by the install wizard) or key;
# the kiosk user is display-only and must never be reachable; root disabled.
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

    # Per-device keys written by the install wizard. Root-owned path (not the
    # user's home) so the installer needs no uid bookkeeping, and separate from
    # /etc/ssh/authorized_keys.d/%u which the module manages for baked adminKeys.
    authorizedKeysFiles = [ "${cfg.stateDir}/authorized_keys/%u" ];

    # extraConfig lands at the end of sshd_config, so the Match block scopes
    # correctly: password auth for the admin only, everything else key-only.
    extraConfig = ''
      Match User ${cfg.adminUser}
        PasswordAuthentication yes
    '';
  };
}
