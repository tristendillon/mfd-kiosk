{
  description = "MFD kiosk — declarative NixOS appliance (cage + cog)";

  inputs = {
    # TODO: confirm/bump the channel for your build host. nixos-25.11 is a safe
    # stable as of 2026; `nix flake update` to refresh flake.lock.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        # The kiosk appliance itself.
        kiosk = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self; };
          modules = [
            disko.nixosModules.disko
            ./hosts/kiosk/configuration.nix
          ];
        };

        # A bootable installer ISO that carries this flake and the `mfd-install`
        # helper (guided disko partition -> nixos-install -> token prompt).
        installerIso = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self; };
          modules = [ ./modules/installer.nix ];
        };
      };

      # Convenience: `nix build .#iso`
      packages.${system}.iso =
        self.nixosConfigurations.installerIso.config.system.build.isoImage;
    };
}
