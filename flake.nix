{
  description = "MFD kiosk — Nix dev environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    claude-code.url = "github:sadjow/claude-code-nix";
  };

  # NOTE: this is the DEV-ENVIRONMENT flake (what direnv `use flake` and the dev
  # container load). The kiosk appliance / installer ISO is a SEPARATE flake under
  # ./os so it can keep a stable nixpkgs pin independent of this unstable one.
  #   nix build ./os#iso
  #   nixos-rebuild build-vm --flake ./os#kiosk   (needs qemu; we test in VMware)
  outputs = { self, nixpkgs, flake-utils, claude-code, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ claude-code.overlays.default ];
        };

        # Shared by local dev and CI — edit this list, not the shells.
        corePackages = with pkgs; [
          nixpkgs-fmt # formatter (matches nix-ide setting in devcontainer.json)
          deadnix # dead-code linter for .nix
          statix # nix anti-pattern linter
          nil # nix language server (nix-ide)
        ];

        # Interactive niceties CI has no use for.
        devOnlyPackages = with pkgs; [
          bashInteractive
          bash-completion
          nix-bash-completions
          pkgs.claude-code
        ];
      in
      {
        devShells = {
          default = pkgs.mkShell {
            packages = corePackages ++ devOnlyPackages;

            BASH_COMPLETION_PATH = "${pkgs.bash-completion}/etc/profile.d/bash_completion.sh";

            shellHook = ''
              echo "Nix devShell ready — $(nix --version). Build the appliance with: nix build ./os#iso"
            '';
          };

          ci = pkgs.mkShell {
            packages = corePackages;
          };
        };
      });
}
