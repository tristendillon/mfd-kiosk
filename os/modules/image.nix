{ config, pkgs, lib, modulesPath, ... }:

# Builds the kiosk as a prebuilt, compressed disk image (`system.build.image`)
# via systemd-repart — NOT an in-place nixos-install. The image is flashed onto
# the board's eMMC by the USB flasher (see flasher.nix), so nothing builds on the
# 2 GB board at provision time. Replaces hosts/kiosk/disk.nix (disko).
#
# Why repart and not disko's diskoImages: `systemd-repart` runs directly in the
# Nix sandbox with no qemu/VM, which matters on build hosts without /dev/kvm.
# The cost is that repart installs no bootloader, so we make the image bootable
# ourselves with a UKI + systemd-boot dropped at the EFI removable-media fallback
# path. That fallback is required because the image is flashed offline: there is
# no running system to write an NVRAM boot entry, so firmware must auto-discover
# the loader at /EFI/BOOT/BOOTX64.EFI.
{
  imports = [ "${modulesPath}/image/repart.nix" ];

  # No conventional bootloader install hook; we populate the ESP by hand below.
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.uki.name = "mfd-kiosk";
  boot.initrd.systemd.enable = true; # needed for initrd repart grow (and smaller initrd)

  image.repart = {
    name = "mfd-kiosk";
    compression = {
      enable = true;
      algorithm = "zstd";
      level = 9;
    };
    partitions = {
      "00-esp" = {
        contents = {
          # Removable-media fallback: firmware always tries this path.
          "/EFI/BOOT/BOOTX64.EFI".source =
            "${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootx64.efi";
          # The Unified Kernel Image systemd-boot auto-discovers.
          "/EFI/Linux/${config.boot.uki.name}.efi".source =
            "${config.system.build.uki}/${config.boot.uki.name}.efi";
        };
        repartConfig = {
          Type = "esp";
          Format = "vfat";
          Label = "esp"; # GPT partlabel; hardware.nix mounts /boot by-partlabel/esp
          SizeMinBytes = "512M";
          SizeMaxBytes = "512M";
        };
      };
      "10-root" = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Type = "root";
          Format = "ext4";
          Label = "nixos";
          Minimize = "guess"; # build a COMPACT root; grown to fill the disk on first boot
        };
      };
    };
  };

  # First boot: grow the (last) root partition + ext4 to fill the real 8 GB disk.
  # repart matches the existing partition by Type GUID, relocates the GPT backup
  # header to the true end of the disk, and GrowFileSystem resizes ext4 online.
  # Fallback if this ever misbehaves: drop these two and set boot.growPartition.
  boot.initrd.systemd.repart.enable = true;
  systemd.repart.partitions."10-root" = {
    Type = "root";
    GrowFileSystem = "yes";
  };
}
