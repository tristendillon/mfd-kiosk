{ config, pkgs, lib, modulesPath, kioskAttr ? "kiosk", ... }:

# The flasher as a REAL GPT raw disk image (`.img`) — a conventional FAT32 EFI
# System Partition with the removable-media loader plus an ext4 root carrying
# the flasher system and the kiosk payload. Written byte-for-byte to a stick
# (Rufus DD mode / Etcher / dd), firmware sees an ordinary GPT disk — no
# isohybrid tricks. This is what finicky Aptio-class UEFI firmware (e.g. the
# MeLE PCG02 compute stick) gets when it refuses to boot the ISO layout.
#
# Same build mechanism as the kiosk image itself (see image.nix for the
# repart-vs-disko rationale and the removable-media boot path explanation).
# All installer behavior lives in flasher-common.nix.
let
  isDebug = kioskAttr != "kiosk";
in
{
  imports = [
    "${modulesPath}/image/repart.nix"
    ./flasher-common.nix
  ];

  # Payload lives as plain files on the root fs (repart CopyFiles below), so
  # the store closure never carries the multi-GB blob.
  mfd.flasher.payloadDir = "/mfd-installer";

  # The driver/firmware breadth the installer ISO gets from its profile
  # (usb_storage/uas/xhci in the initrd, redistributable Wi-Fi firmware, ...).
  hardware.enableAllHardware = true;

  # No conventional bootloader install hook; repart lays out the ESP by hand
  # below, exactly like the kiosk image.
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.uki.name = "mfd-flasher";
  boot.initrd.systemd.enable = true; # needed for initrd repart grow (and smaller initrd)

  # DISTINCT labels from the kiosk image (nixos / esp): the wizard's freshly
  # flashed target keeps LABEL=nixos, and a stick left inserted must never win
  # the installed kiosk's by-label/nixos or by-partlabel/esp lookups
  # (hosts/kiosk/hardware.nix mounts both globally).
  fileSystems."/" = {
    device = "/dev/disk/by-label/mfd-flasher";
    fsType = "ext4";
  };
  # No /boot mount: nothing on the running flasher touches its own ESP.

  system.stateVersion = "26.05";

  image.repart = {
    name = "mfd-kiosk-flasher-usb${lib.optionalString isDebug "-debug"}";
    # Force FAT32: at 512M mkfs.vfat would pick FAT16, and appeasing finicky
    # UEFI firmware is the whole point of this artifact.
    mkfsOptions.vfat = [ "-F" "32" ];
    # Level 3, not 9: most of the image is the embedded payload, which is
    # already zstd-compressed — higher levels just burn CI minutes on it.
    compression = {
      enable = true;
      algorithm = "zstd";
      level = 3;
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
          # timeout 0: boot the (single) UKI immediately, no menu; editor no:
          # no kernel cmdline editing at the console. See image.nix for the
          # OsIndications background.
          "/loader/loader.conf".source = pkgs.writeText "mfd-flasher-loader.conf" ''
            timeout 0
            editor no
          '';
        };
        repartConfig = {
          Type = "esp";
          Format = "vfat";
          Label = "flasher-esp";
          SizeMinBytes = "512M";
          SizeMaxBytes = "512M";
        };
      };
      "10-root" = {
        storePaths = [ config.system.build.toplevel ];
        # The payload as plain files, copied into the ext4 fs at build time —
        # NOT part of the toplevel closure (the wizard references it only via
        # the /mfd-installer runtime string; see the payloadDir option).
        contents = {
          "/mfd-installer/mfd-kiosk.raw.zst".source =
            "${config.mfd.flasher.payloadPackage}/mfd-kiosk.raw.zst";
          "/mfd-installer/mfd-kiosk.raw.zst.sha256".source =
            "${config.mfd.flasher.payloadPackage}/mfd-kiosk.raw.zst.sha256";
        };
        repartConfig = {
          Type = "root";
          Format = "ext4";
          Label = "mfd-flasher";
          Minimize = "guess"; # ship a COMPACT image; grown on first boot (below)
        };
      };
    };
  };

  # First boot of the STICK: grow root + ext4 to fill it, so journald, /tmp and
  # iwd's live Wi-Fi test have headroom (a minimized ext4 is nearly full).
  boot.initrd.systemd.repart.enable = true;
  systemd.repart.partitions."10-root" = {
    Type = "root";
    GrowFileSystem = "yes";
  };
}
