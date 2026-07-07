{
  description = "MFD kiosk — declarative NixOS appliance";

  inputs = {
    # Current stable NixOS. Bumped off 25.11 once it hit end-of-support
    # (2026-06-30) — an EOL release makes systemd print a red "past its
    # end-of-support date" warning on every boot (initrd + stage-2). The browser
    # is firefox-esr (see modules/browser.nix), carried across releases, so
    # nothing forces an older pin.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # The kiosk appliance, optionally with extra modules spliced in (used to
      # flip mfd.kiosk.debug for the diagnostic variant — see modules/debug.nix).
      mkKiosk = extraModules: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; };
        modules = [ ./hosts/kiosk/configuration.nix ] ++ extraModules;
      };

      # A flasher ISO carrying the kiosk image named by `kioskAttr`
      # (nixosConfigurations.<kioskAttr>). flasher.nix reads that specialArg to
      # decide which image to embed and how to name the ISO.
      mkFlasher = kioskAttr: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self kioskAttr; };
        modules = [ ./modules/flasher.nix ];
      };

      # `nix run .#iso` / `.#isoDebug` — build an ISO and drop a REAL
      # (dereferenced) copy at `dest`. `nix build` can only ever produce a
      # /nix/store symlink; this copies the artifact out so it's directly
      # transferable (e.g. to a Windows host), failing loudly on a truncated copy.
      mkIsoApp = { isoPkg, dest }:
        let
          copyIso = pkgs.writeShellApplication {
            name = "mfd-build-iso";
            runtimeInputs = [ pkgs.coreutils pkgs.diffutils ];
            text = ''
              #!/usr/bin/env bash
              shopt -s nullglob
              isos=("${isoPkg}"/iso/*.iso)
              if [ ''${#isos[@]} -eq 0 ]; then
                echo "No .iso found in the build output." >&2
                exit 1
              fi
              dest="${dest}"
              mkdir -p "$(dirname "$dest")"
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
        {
          type = "app";
          program = "${copyIso}/bin/mfd-build-iso";
        };
    in
    {
      nixosConfigurations = {
        # The kiosk appliance itself. Built as a prebuilt disk image
        # (config.system.build.image, see modules/image.nix), not installed in
        # place — the image is flashed onto the board's eMMC by the flasher.
        kiosk = mkKiosk [ ];

        # Same image with mfd.kiosk.debug on: un-quiet boot + a passwordless
        # `technician` autologin shell on tty1, for bring-up on new/untested
        # boards (e.g. the Cherry Trail Intel Compute Stick). Do NOT ship this to
        # production or attach it to a public release — anyone with physical
        # access gets a root-capable shell with no token and no password.
        kioskDebug = mkKiosk [ { mfd.kiosk.debug = true; } ];

        # A bootable USB flasher that CARRIES the prebuilt kiosk image and ships
        # `mfd-install` (stream the image onto the internal disk, RAM-free).
        flasherIso = mkFlasher "kiosk";

        # The same flasher, but carrying the DEBUG kiosk image above.
        flasherIsoDebug = mkFlasher "kioskDebug";
      };

      # Convenience: `nix build .#iso` (the flasher USB image) and `.#image`
      # (the bare kiosk disk image, for direct `dd` in the lab); `*Debug`
      # variants carry the diagnostic image.
      packages.${system} = {
        iso = self.nixosConfigurations.flasherIso.config.system.build.isoImage;
        isoDebug = self.nixosConfigurations.flasherIsoDebug.config.system.build.isoImage;
        image = self.nixosConfigurations.kiosk.config.system.build.image;
        imageDebug = self.nixosConfigurations.kioskDebug.config.system.build.image;
      };

      # `nix run .#iso` / `.#isoDebug` — build the ISO and copy a real file into
      # ./dist/ (see mkIsoApp above). Distinct filenames so both can coexist.
      apps.${system} = {
        iso = mkIsoApp {
          isoPkg = self.packages.${system}.iso;
          dest = "dist/mfd-kiosk-flasher.iso";
        };
        isoDebug = mkIsoApp {
          isoPkg = self.packages.${system}.isoDebug;
          dest = "dist/mfd-kiosk-flasher-debug.iso";
        };
      };
    };
}
