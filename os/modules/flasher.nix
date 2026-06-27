{ self, pkgs, lib, modulesPath, ... }:

# USB flasher live environment. Replaces installer.nix's in-place disko +
# nixos-install (which staged the closure in the live RAM-disk and OOM'd on 2 GB
# boards). Instead it CARRIES the prebuilt, compressed kiosk image and streams it
# straight onto the board's internal disk with `zstd -dc | dd` — copying bytes
# needs almost no RAM, so 2 GB is plenty at provision time.
let
  kiosk = self.nixosConfigurations.kiosk.config;
  # The finished kiosk disk image (a dir containing mfd-kiosk_<ver>.raw.zst),
  # built without qemu via systemd-repart. See image.nix.
  kioskImage = kiosk.system.build.image;

  # The image + a checksum under STABLE names, copied out so we can drop them
  # onto the ISO9660 filesystem directly (see isoImage.contents below) instead
  # of letting the multi-GB blob land inside nix-store.squashfs. Keeping the
  # boot-critical store squashfs small (just the flasher's own closure) is what
  # makes Stage 1 survive a truncated ISO — the store mount no longer has to read
  # into the image tail. The checksum lets mfd-flash refuse a corrupt medium.
  kioskFlash = pkgs.runCommand "mfd-kiosk-flash" { } ''
    mkdir -p "$out"
    f=("${kioskImage}"/*.raw.zst)
    cp "''${f[0]}" "$out/mfd-kiosk.raw.zst"
    ( cd "$out" && sha256sum mfd-kiosk.raw.zst > mfd-kiosk.raw.zst.sha256 )
  '';
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  image.fileName = lib.mkForce "mfd-kiosk-flasher.iso";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  networking.hostName = "mfd-flasher";

  # SSH into the live flasher for headless provisioning. Reuse the technician
  # key(s) baked into the kiosk so the same credential flashes remotely.
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = kiosk.mfd.kiosk.adminKeys;

  # Carry the compressed image (+ its checksum) as plain files on the ISO9660
  # filesystem, NOT inside nix-store.squashfs. The live CD is mounted at /iso, so
  # mfd-flash reads them from there. This keeps the store squashfs tiny and the
  # boot robust against a truncated ISO; integrity is enforced at flash time.
  isoImage.contents = [
    { source = "${kioskFlash}/mfd-kiosk.raw.zst"; target = "/mfd-kiosk.raw.zst"; }
    { source = "${kioskFlash}/mfd-kiosk.raw.zst.sha256"; target = "/mfd-kiosk.raw.zst.sha256"; }
  ];

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "mfd-flash";
      runtimeInputs = with pkgs; [ util-linux coreutils zstd ];
      text = ''
        img="/iso/mfd-kiosk.raw.zst"
        if [ ! -r "$img" ]; then
          echo "No image found at $img (is this the flasher USB?)" >&2
          exit 1
        fi

        # Refuse a truncated/corrupt medium up front rather than dd'ing garbage.
        echo ">> Verifying image integrity..."
        if ! ( cd /iso && sha256sum -c mfd-kiosk.raw.zst.sha256 ); then
          echo "Image on this USB is corrupt/truncated (checksum mismatch)." >&2
          echo "Re-burn the ISO and verify the write, then try again." >&2
          exit 1
        fi

        echo "=== MFD kiosk flasher ==="
        echo
        lsblk -dpno NAME,SIZE,MODEL,TRAN
        echo
        read -rp "Target INTERNAL disk to ERASE (e.g. /dev/mmcblk0, /dev/sda): " disk
        if [ ! -b "$disk" ]; then
          echo "Not a block device: $disk" >&2
          exit 1
        fi
        read -rp "This will WIPE $disk. Type ERASE to continue: " confirm
        if [ "$confirm" != "ERASE" ]; then
          echo "Aborted."
          exit 1
        fi

        echo ">> Streaming image to $disk (RAM-free)..."
        zstd -dc "$img" | dd of="$disk" bs=8M conv=fsync status=progress
        sync
        partprobe "$disk" || true

        echo
        echo "Done. Remove the USB and reboot. The root partition grows to fill"
        echo "the disk on first boot. Then, over SSH as the technician, run:"
        echo "    sudo mfd-set-token"
      '';
    })
  ];
}
