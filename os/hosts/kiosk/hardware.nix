{ lib, ... }:

# Generic hardware profile so a SINGLE image boots on varied kiosk boards
# (Intel N100, AMD APUs, typical thin clients) without a per-board
# hardware-configuration.nix. Drivers/firmware load by PCI id at boot.
{
  # Common storage/USB/input controllers + virtio for VM testing.
  boot.initrd.availableKernelModules = [
    "ahci"
    "nvme"
    "xhci_pci"
    "ehci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
  ];

  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];

  # Microcode + redistributable firmware for both vendors (see slim.nix for the
  # firmware toggle). Cheap insurance for a mixed Intel/AMD fleet.
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
