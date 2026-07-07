{ config, lib, ... }:

# Small, reversible performance/wear tuning for the display appliance. Every
# knob here is low-risk and aimed at one of three goals: a quieter/cleaner boot
# console, snappier map/dashboard rendering, or fewer writes to the eMMC/SSD so
# the flash lasts. The box reboots daily, so shutdown/boot speed matters too.
let
  debug = config.mfd.kiosk.debug;
in
{
  boot.kernelParams = [
    # Cherry Trail / Bay Trail Atom SoCs (e.g. the Intel Compute Stick) hard-hang
    # in deep C-states — the classic, widely-cited "Atom random freeze". Capping
    # C-states is the standard cure. No-op on N100/AMD/VMware (they either don't
    # expose these C-states or ignore the param), so it's safe fleet-wide.
    "intel_idle.max_cstate=1"
  ]
  # Quieter, cleaner boot console (visible in VMware). Drop kernel/udev chatter
  # to warnings+; systemd.show_status=auto shows unit status only when something
  # is slow or fails, so a healthy boot stays tidy. Suppressed in debug mode
  # (debug.nix) so bring-up on a new board can actually read the boot.
  ++ lib.optionals (!debug) [
    "quiet"
    "loglevel=3"
    "udev.log_level=3"
    "rd.udev.log_level=3"
    "systemd.show_status=auto"
  ];

  # A kiosk never runs virtual machines, so the KVM hypervisor modules are dead
  # weight. The kernel auto-loads kvm-intel/kvm-amd by CPU vendor; under VMware
  # (no nested VT-x exposed) that attempt fails and prints a red-herring
  # "kvm_intel: VMX not supported by CPU N" on the console — the last line before
  # the intentionally-blank kiosk screen, so it reads like a boot error when it
  # isn't. Blacklisting stops the load attempt entirely: clean console in the VM,
  # one less unused module on the real board.
  boot.blacklistedKernelModules = [ "kvm-intel" "kvm-amd" ];

  # Tuned for the zstd zram swap configured in slim.nix.
  boot.kernel.sysctl = {
    # High swappiness favors pushing cold pages into compressed RAM swap over
    # reclaiming file cache — cheap on zram, keeps the browser responsive.
    "vm.swappiness" = 180;
    # page-cluster=0 => single-page swap reads (no readahead), which is the
    # right call for zram: reads are already fast and readahead just wastes work.
    "vm.page-cluster" = 0;
    # Keep the dentry/inode cache warmer (lower reclaim pressure) for snappier
    # repeated filesystem access.
    "vm.vfs_cache_pressure" = 50;
  };

  # Snappier map/dashboard rendering on N100 boards. No-op in VMware (no cpufreq
  # interface is exposed to the guest) but harmless there. mkDefault so a board
  # profile can override if needed.
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";

  # Weekly TRIM for sustained eMMC/SSD write performance and flash longevity.
  services.fstrim.enable = true;

  # /tmp in RAM (backed by zram under memory pressure): faster temp I/O and
  # fewer eMMC writes. Nothing on this appliance needs a large persistent /tmp.
  boot.tmp.useTmpfs = true;

  # Faster reboot/shutdown (the box reboots daily): cap how long systemd waits
  # for a unit to stop before killing it. 15s is generous for these services yet
  # well under the 90s default. StartSec is left at its default. Written to
  # system.conf via the typed systemd.settings.Manager option (25.11).
  systemd.settings.Manager.DefaultTimeoutStopSec = "15s";

  # NOTE: boot.loader.timeout is intentionally NOT set. systemd-boot is disabled
  # (mkForce false in image.nix; the UKI is auto-discovered via the
  # removable-media fallback), so that option writes no loader.conf and would be
  # a silently-dead no-op here.
}
