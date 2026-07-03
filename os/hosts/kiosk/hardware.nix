{ lib, ... }:

# Generic hardware profile so a SINGLE image boots on varied kiosk boards
# (Intel N100, AMD APUs, typical thin clients) without a per-board
# hardware-configuration.nix. Drivers/firmware load by PCI id at boot.
{
  # Common storage/USB/input controllers + virtio for VM testing. eMMC modules
  # (mmc_block/sdhci*) are essential: the target boards boot from internal eMMC
  # (/dev/mmcblk0) and without these the initrd can't find or mount root.
  boot.initrd.availableKernelModules = [
    "ahci"
    "nvme"
    "mmc_block"
    "sdhci"
    "sdhci_pci"
    "sdhci_acpi"
    "xhci_pci"
    "ehci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    # VMware SCSI controllers (firmware can read the disk to load the UKI, but the
    # kernel needs these or root vanishes after handoff → emergency mode). Covers
    # Paravirtual (PVSCSI), LSI Logic Parallel, and LSI Logic SAS.
    "vmw_pvscsi"
    "mptspi"
    "mpt3sas"
  ];

  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];

  # Root + ESP are identified by label/partlabel from the prebuilt image
  # (see image.nix).
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    # noatime: don't write an access timestamp on every read — fewer metadata
    # writes (less eMMC wear) and slightly faster reads. /boot is left as-is.
    options = [ "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/esp";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  # Microcode + redistributable firmware for both vendors (see slim.nix for the
  # firmware toggle). Cheap insurance for a mixed Intel/AMD fleet.
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
