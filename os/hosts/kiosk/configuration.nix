{ lib, ... }:

{
  imports = [
    ../../modules/options.nix
    ./hardware.nix
    ../../modules/image.nix
    ../../modules/minimal.nix
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPx4F6/sjRoTRcGcE+BZhP2NTRrPTFAu6QV4JIVivElc tristen@windows"
    ];

    # NOTE: inert now — the prebuilt image is disk-agnostic and the USB flasher
    # (mfd-flash) prompts for the target disk at flash time. Kept only so older
    # references don't break; it no longer affects the build.
    diskDevice = "/dev/sda";
  };

  # TODO: confirm the timezone for this department.
  time.timeZone = lib.mkDefault "America/Chicago";

  # Wired networking by default via systemd-networkd + DHCP.
  systemd.network.enable = true;
  networking.useNetworkd = true;
  networking.useDHCP = lib.mkDefault true;

  # Boot is handled by the UKI + systemd-boot fallback baked into the image
  # (see modules/image.nix); no on-disk bootloader install step here.

  # Pin the release you first installed against; do not bump casually.
  system.stateVersion = "25.11";
}
