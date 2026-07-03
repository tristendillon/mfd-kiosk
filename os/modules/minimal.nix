{ modulesPath, lib, ... }:

# Footprint trims so the closure fits the 8 GB eMMC with room to spare. The
# appliance is immutable (re-flashed to update, never `nixos-rebuild`'d on the
# board), so on-device installer/build tooling is dead weight we can drop.
{
  imports = [
    "${modulesPath}/profiles/minimal.nix"
    # NOTE: profiles/perlless.nix is NOT imported. It was originally dropped
    # because cog → webkitgtk dragged perl into the closure (via gperftools'
    # `pprof` and aspell/hspell), which trips perlless'
    # `system.forbiddenDependenciesRegexes = ["perl"]`. The browser is now
    # firefox-esr, so the webkit constraint is gone — but Firefox has its own
    # build-time perl users, so re-enabling perlless still needs verification.
    # That is a deliberate follow-up (the "slim down later" task), not done here.
    # profiles/minimal.nix above already gives the real footprint wins (docs off,
    # environment.defaultPackages = [], no containers/udisks2).
  ];

  # No nixos-install / nixos-enter / nixos-generate on an immutable appliance.
  system.disableInstallerTools = true;

  # Smaller, faster initrd (also required by the repart grow in image.nix).
  boot.initrd.systemd.enable = true;

  # Few generations ever exist (re-flash model); keep the boot menu/store tiny.
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 2;

  # Hardlink-dedup identical store files on the eMMC.
  nix.settings.auto-optimise-store = true;
}
