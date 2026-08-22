{ config, lib, modulesPath, kioskAttr ? "kiosk", ... }:

# The flasher as a hybrid GPT/MBR ISO (installation-cd based). Boots as a CD in
# VMs and as a USB stick on most firmware; some finicky UEFI implementations
# refuse the isohybrid layout — those get the raw GPT USB image instead (see
# flasher-usb.nix). All installer behavior lives in flasher-common.nix.
let
  isDebug = kioskAttr != "kiosk";
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ./flasher-common.nix
  ];

  # The live CD is loop-mounted at /iso, so the wizard reads the payload there.
  mfd.flasher.payloadDir = "/iso";

  image.fileName = lib.mkForce "mfd-kiosk-flasher${lib.optionalString isDebug "-debug"}.iso";

  # 26.05's installer profile enables NetworkManager (for nmtui), whose default
  # wpa_supplicant backend flips networking.wireless.enable = true — which is now
  # mutually exclusive with iwd (assertion in the iwd module). We don't use NM:
  # the wizard drives iwctl directly and would fight NM's connection management,
  # so force it off and keep raw iwd (the flasher's pre-26.05 behavior). Wired
  # DHCP for headless SSH provisioning still comes up via the installer default.
  networking.networkmanager.enable = lib.mkForce false;

  # The live flasher boots from the ISO squashfs and never imports a ZFS pool
  # (ZFS support is only carried because the installer profile bundles it), so
  # adopt 26.11's upcoming default explicitly and silence the boot-time warning.
  boot.zfs.forceImportRoot = false;

  # Carry the compressed image (+ its checksum) as plain files on the ISO9660
  # filesystem, NOT inside nix-store.squashfs. The live CD is mounted at /iso, so
  # the wizard reads them from there. This keeps the store squashfs tiny and the
  # boot robust against a truncated ISO; integrity is enforced at flash time.
  isoImage.contents = [
    { source = "${config.mfd.flasher.payloadPackage}/mfd-kiosk.raw.zst"; target = "/mfd-kiosk.raw.zst"; }
    { source = "${config.mfd.flasher.payloadPackage}/mfd-kiosk.raw.zst.sha256"; target = "/mfd-kiosk.raw.zst.sha256"; }
  ];
}
