{ lib, ... }:

{
  imports = [
    ../../modules/options.nix
    ./hardware.nix
    ./disk.nix
    ../../modules/browser.nix
    ../../modules/user.nix
    ../../modules/ssh.nix
    ../../modules/slim.nix
    ../../modules/maintenance.nix
    ../../modules/secrets.nix
  ];

  networking.hostName = "mfd-kiosk";

  # ---- Site configuration ---------------------------------------------------
  mfd.kiosk = {
    baseUrl = "https://mfd.alertdashboard.com";
    rebootTime = "04:00";

    # TODO: paste the technician's SSH public key(s) here. Without at least one
    # key you will not be able to log in (PasswordAuthentication is off).
    adminKeys = [
      # "ssh-ed25519 AAAA... technician@laptop"
    ];

    # TODO: set the real install disk per board model (e.g. /dev/nvme0n1).
    diskDevice = "/dev/sda";
  };

  # TODO: confirm the timezone for this department.
  time.timeZone = lib.mkDefault "America/Chicago";

  # Wired networking by default via systemd-networkd + DHCP.
  systemd.network.enable = true;
  networking.useNetworkd = true;
  networking.useDHCP = lib.mkDefault true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Pin the release you first installed against; do not bump casually.
  system.stateVersion = "25.11";
}
