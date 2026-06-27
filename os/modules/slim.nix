{ lib, ... }:

# Replaces slim.sh and the firmware logic in packages.sh. Most of the old work
# (purging snap/cloud-init/kdump/unattended-upgrades) is unnecessary: minimal
# NixOS never installs them in the first place.
{
  # Compressed RAM swap so a single tab can't OOM a low-RAM box. On a 2 GB
  # display appliance a larger pool is pure upside: zstd compresses the browser's
  # dirty heap ~3x, so 100% logical (~2 GB) costs only a few hundred MB physical
  # while giving Google Maps real headroom.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
  };

  # Last-resort guard for 2 GB boards: kill the worst memory hog before the
  # kernel OOM-killer stalls the box. cage's Restart=always (browser.nix) brings
  # the kiosk straight back, so a runaway tab self-heals.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
  };

  # Cap journal disk usage (matches journald-kiosk.conf).
  services.journald.extraConfig = ''
    SystemMaxUse=50M
  '';

  # An appliance has no console reader — drop docs to shrink the closure.
  documentation.enable = false;
  documentation.nixos.enable = false;
  documentation.man.enable = lib.mkDefault false;

  # No default toolbox on a kiosk.
  environment.defaultPackages = lib.mkForce [ ];

  # Firmware for whatever board this lands on (Intel i915 / AMD amdgpu). One
  # image, drivers load by PCI id — this replaces the per-board PCI-vendor purge.
  hardware.enableRedistributableFirmware = true;

  # Display-only: nothing here needs print/mDNS discovery.
  services.printing.enable = false;
  services.avahi.enable = false;

  # Trim other defaults that pull weight on a headless-ish appliance.
  xdg.autostart.enable = false;
  xdg.mime.enable = lib.mkForce true; # firefox wants shared-mime-info (minimal.nix disables it)
}
