{ modulesPath, lib, ... }:

# Footprint trims so the closure fits the 8 GB eMMC with room to spare. The
# appliance is immutable (re-flashed to update, never `nixos-rebuild`'d on the
# board), so on-device installer/build tooling is dead weight we can drop.
{
  imports = [
    "${modulesPath}/profiles/minimal.nix"
    # NOTE: profiles/perlless.nix is NOT imported. The old cog → webkitgtk perl
    # leak is gone (browser is firefox-esr now), but perl STILL enters the
    # closure and trips perlless' `forbiddenDependenciesRegexes = ["perl"]`.
    # Verified empirically: importing perlless fails the toplevel build, and
    # `nix why-depends` traces every remaining perl path to one runtime source —
    #   firefox-esr → xdg-utils → perl (xdg-utils is a bundle of perl scripts;
    #   it pulls File-MimeInfo, Net-DBus, XML-Parser, libwww-perl, …).
    # Dropping xdg-utils from firefox's closure is the unsolved blocker; until
    # then perlless stays off. profiles/minimal.nix above still gives the real
    # footprint wins (docs off, environment.defaultPackages = [], no
    # containers/udisks2).
  ];

  # No nixos-install / nixos-enter / nixos-generate on an immutable appliance.
  system.disableInstallerTools = true;

  # Smaller, faster initrd (also required by the repart grow in image.nix).
  boot.initrd.systemd.enable = true;

  # Immutable single-generation appliance; keep the boot menu/store tiny.
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 1;

  # The appliance never builds or rebuilds itself (re-flashed to update), so the
  # Nix daemon + CLI are pure dead weight — drop them from the closure entirely.
  # This also makes auto-optimise-store moot (no daemon to run it), so it's gone.
  nix.enable = false;
}
