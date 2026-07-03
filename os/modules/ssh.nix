{ config, lib, ... }:

# Admin-only SSH: password (set by the install wizard) or key; the kiosk user is
# display-only and must never be reachable; root disabled.
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

  # nixpkgs' sshd module keys the sshd PAM stack's pam_unix off the GLOBAL
  # PasswordAuthentication (sshd.nix: `unixAuth = PasswordAuthentication == true`).
  # We set that false to make the fleet key-only by default and re-enable password
  # auth for the admin via the Match block above — but that only flips sshd's
  # `password` METHOD, not PAM. With UsePAM = yes the credential is still verified
  # by PAM, whose unixAuth is now off, so EVERY admin password was rejected while
  # console login (the `login` PAM stack, unixAuth on) kept working. Force pam_unix
  # back on for sshd. Safe: only the admin's Match block exposes the password
  # prompt at all (kiosk is DenyUsers, root login is off), so this opens nothing
  # the Match doesn't already scope. mkForce overrides the module's own
  # PasswordAuthentication-derived `unixAuth = false`.
  security.pam.services.sshd.unixAuth = lib.mkForce true;
}
