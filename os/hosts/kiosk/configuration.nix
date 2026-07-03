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
    ../../modules/perf.nix
    ../../modules/reliability.nix
    ../../modules/maintenance.nix
    ../../modules/secrets.nix
    ../../modules/identity.nix
  ];

  # Empty = no static hostname baked into the image. The real per-device name
  # (e.g. mfd-fh-05-kiosk) is entered in the install wizard and applied at boot
  # from /var/lib/mfd/hostname by mfd-hostname.service (identity.nix).
  networking.hostName = "";

  # ---- Site configuration ---------------------------------------------------
  mfd.kiosk = {
    # DEFAULT dashboard base URL offered by the install wizard; the effective
    # per-device value is entered there and stored in /var/lib/mfd/base-url.
    baseUrl = "https://mfd.alertdashboard.com";

    # Optional fleet-wide recovery key(s). Per-device credentials (technician
    # password + SSH keys) are collected by the install wizard instead.
    adminKeys = [];
  };

  # Best-effort IP-based timezone at boot (tzupdate sets time.timeZone = null
  # for us). Falls back to UTC when offline/undetectable, which shifts the daily
  # reboot but breaks nothing.
  services.tzupdate.enable = true;

  # Wired networking by default via systemd-networkd + DHCP.
  systemd.network.enable = true;
  networking.useNetworkd = true;
  networking.useDHCP = lib.mkDefault true;

  # A kiosk is wired OR wireless — one of the two links is usually unplugged.
  # By default wait-online wants EVERY managed interface configured, so the
  # dangling one stalls boot ("Wait for Network to be Configured") and fails
  # network-online (tzupdate etc.). Any one working interface is enough.
  systemd.network.wait-online.anyInterface = true;

  # Bound the wait so a genuinely-offline box reaches the login/blank screen
  # sooner instead of stalling on the ~120s default. 30s is ample for DHCP.
  systemd.network.wait-online.timeout = 30;

  # Optional Wi-Fi via iwd (lighter than wpa_supplicant, integrates natively
  # with systemd-networkd). The radio stays idle unless the install wizard
  # stamped credentials into /var/lib/iwd on the flashed root; ethernet is
  # preferred when both links are up. With useNetworkd + useDHCP, NixOS gives
  # the generated wireless DHCP network a higher RouteMetric (1025) than wired
  # (1024, the systemd default) for both IPv4 and IPv6, so a live ethernet link
  # always wins the default route — no explicit metric override needed.
  networking.wireless.iwd.enable = true;

  # Boot is handled by the UKI + systemd-boot fallback baked into the image
  # (see modules/image.nix); no on-disk bootloader install step here.

  # Pin the release you first installed against; do not bump casually.
  system.stateVersion = "25.11";
}
