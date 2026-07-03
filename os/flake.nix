{
  description = "MFD kiosk — declarative NixOS appliance";

  inputs = {
    # Tracks the release that matches system.stateVersion (25.11). The browser is
    # firefox-esr (see modules/browser.nix), which is carried across releases, so
    # nothing forces an older pin.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations = {
        # The kiosk appliance itself. Built as a prebuilt disk image
        # (config.system.build.image, see modules/image.nix), not installed in
        # place — the image is flashed onto the board's eMMC by the flasher.
        kiosk = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self; };
          modules = [ ./hosts/kiosk/configuration.nix ];
        };

        # A bootable USB flasher that CARRIES the prebuilt kiosk image and ships
        # `mfd-flash` (stream the image onto the internal disk, RAM-free).
        flasherIso = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self; };
          modules = [ ./modules/flasher.nix ];
        };
      };

      # Convenience: `nix build .#iso` (the flasher USB image) and `.#image`
      # (the bare kiosk disk image, for direct `dd` in the lab).
      packages.${system} = {
        iso = self.nixosConfigurations.flasherIso.config.system.build.isoImage;
        image = self.nixosConfigurations.kiosk.config.system.build.image;
      };

      # `nix run .#iso` — build the flasher ISO and drop a REAL (dereferenced)
      # copy at ./dist/mfd-kiosk-flasher.iso relative to the current directory.
      # `nix build` can only ever produce a /nix/store symlink; this copies the
      # artifact out so it's directly transferable (e.g. to a Windows host).
      apps.${system}.iso = {
        type = "app";
        program =
          let
            copyIso = pkgs.writeShellApplication {
              name = "mfd-build-iso";
              runtimeInputs = [ pkgs.coreutils pkgs.diffutils ];
              text = ''
                #!/usr/bin/env bash
                shopt -s nullglob
                isos=("${self.packages.${system}.iso}"/iso/*.iso)
                if [ ''${#isos[@]} -eq 0 ]; then
                  echo "No .iso found in the build output." >&2
                  exit 1
                fi
                mkdir -p dist
                dest="dist/mfd-kiosk-flasher.iso"
                cp -Lf "''${isos[0]}" "$dest"
                # Guard against a truncated copy (e.g. a full disk): a short ISO
                # boots into a Stage-1 squashfs I/O error, so fail loudly here.
                if ! cmp -s "''${isos[0]}" "$dest"; then
                  echo "Copy to $dest is truncated/mismatched (disk full?). Aborting." >&2
                  rm -f "$dest"
                  exit 1
                fi
                chmod u+w "$dest"   # store files are read-only; make the copy writable
                echo "Wrote $dest"
                ls -lh "$dest"
              '';
            };
          in
          "${copyIso}/bin/mfd-build-iso";
      };
    };
}
