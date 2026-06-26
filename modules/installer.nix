{ self, config, pkgs, lib, modulesPath, ... }:

# Custom installer ISO. Boots the standard NixOS minimal installer, carries this
# flake, and ships `mfd-install`: a guided disko partition -> nixos-install ->
# token prompt. Needs network at install time to fetch the system closure.
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  isoImage.isoName = lib.mkForce "mfd-kiosk-installer.iso";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # SSH into the live installer if a head-on install isn't convenient.
  services.openssh.enable = true;
  networking.hostName = "mfd-installer";

  # Embed this flake on the ISO (read-only store path).
  environment.etc."mfd-kiosk/flake".source = self;

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "mfd-install";
      runtimeInputs = with pkgs; [ util-linux coreutils gnused disko nixos-install-tools ];
      text = ''
        echo "=== MFD kiosk installer ==="
        echo
        lsblk -dpno NAME,SIZE,MODEL
        echo
        read -rp "Target disk to ERASE (e.g. /dev/sda, /dev/nvme0n1): " disk
        if [ ! -b "$disk" ]; then
          echo "Not a block device: $disk" >&2
          exit 1
        fi
        read -rp "This will WIPE $disk. Type ERASE to continue: " confirm
        if [ "$confirm" != "ERASE" ]; then
          echo "Aborted."
          exit 1
        fi

        # Work from a writable copy so we can pin the chosen disk.
        work="$(mktemp -d)"
        cp -r /etc/mfd-kiosk/flake/. "$work"/
        chmod -R u+w "$work"
        sed -i "s|diskDevice = \"/dev/sda\";|diskDevice = \"$disk\";|" \
          "$work/hosts/kiosk/configuration.nix"

        echo ">> Partitioning + formatting $disk via disko..."
        disko --mode destroy,format,mount --flake "$work#kiosk"

        echo ">> Installing NixOS..."
        nixos-install --no-root-passwd --flake "$work#kiosk"

        echo ">> Set the dashboard token for this device:"
        nixos-enter --root /mnt -c mfd-set-token

        echo
        echo "Install complete. Remove the USB and reboot."
      '';
    })
  ];
}
