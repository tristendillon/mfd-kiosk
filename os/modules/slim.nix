{ lib, ... }:

# Replaces slim.sh and the firmware logic in packages.sh. Most of the old work
# (purging snap/cloud-init/kdump/unattended-upgrades) is unnecessary: minimal
# NixOS never installs them in the first place.
{
  # Compressed RAM swap so a single tab can't OOM a low-RAM box.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
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
  xdg.mime.enable = lib.mkDefault true; # cog/webkit wants shared-mime-info
}
