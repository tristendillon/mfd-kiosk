{ config, ... }:

# Per-device identity, written by the install wizard (flasher.nix) onto the
# flashed root partition — OUTSIDE the Nix store, because the image itself is
# byte-identical for every device. Files under ${stateDir}:
#   hostname                 -> applied at boot by mfd-hostname (before DHCP)
#   base-url                 -> dashboard base URL, read by mfd-set-token at
#                               token-set time (secrets.nix); falls back to the
#                               baked default (mfd.kiosk.baseUrl) when absent
#   <adminUser>.hash         -> admin password hash (user.nix hashedPasswordFile)
#   authorized_keys/<user>   -> extra sshd AuthorizedKeysFile path (ssh.nix)
# Also stamped by the wizard, but OUTSIDE ${stateDir} (iwd owns its own dir):
#   /var/lib/iwd/<ssid>.psk  -> optional Wi-Fi credentials in iwd's native
#                               format; absent = ethernet-only. iwd's module
#                               manages /var/lib/iwd, so no tmpfiles rule here.
# A raw-dd'd image without these files degrades gracefully: hostname unit
# condition-skips, the admin account falls back to locked, baked adminKeys (if
# any) remain the SSH recovery path.
let
  cfg = config.mfd.kiosk;
in
{
  systemd.tmpfiles.rules = [
    "d ${cfg.stateDir} 0755 root root -"
    "d ${cfg.stateDir}/authorized_keys 0755 root root -"
  ];

  systemd.services.mfd-hostname = {
    description = "Set hostname from ${cfg.stateDir}/hostname";
    wantedBy = [ "sysinit.target" ];
    # Before networkd so the DHCP client sends the real hostname to the server.
    before = [ "network-pre.target" "systemd-networkd.service" "systemd-hostnamed.service" ];
    after = [ "systemd-remount-fs.service" ];
    unitConfig = {
      DefaultDependencies = false;
      ConditionPathExists = "${cfg.stateDir}/hostname";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # Write the kernel hostname directly: hostnamectl needs dbus + hostnamed,
    # neither of which is up this early in boot.
    script = ''
      hn="$(tr -cd 'a-zA-Z0-9-' < ${cfg.stateDir}/hostname)"
      if [ -n "$hn" ]; then
        printf '%s' "$hn" > /proc/sys/kernel/hostname
      fi
    '';
  };
}
