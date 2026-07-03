{ ... }:

# Auto-recovery so the kiosk always comes back on its own. Browser-level
# crash-restart lives in browser.nix (cage Restart=always); this module covers
# the layers below it: a kernel panic/oops reboots instead of hanging on a dark
# screen, and a hardware watchdog resets the box if the whole system wedges.
#
# NOTE: powering back ON after an AC outage (e.g. the weekly generator test) is
# a FIRMWARE setting the OS cannot control — set "Restore on AC Power Loss" to
# "Power On" (or "Last State") in each board's BIOS/UEFI, or the box stays dark
# until someone presses the power button.
{
  boot.kernel.sysctl = {
    # Reboot 10s after a kernel panic instead of sitting dead forever.
    "kernel.panic" = 10;
    # Promote a kernel oops to a full panic so it, too, triggers the reboot.
    "kernel.panic_on_oops" = 1;
  };

  # Hardware watchdog: systemd (PID 1) pings /dev/watchdog every RuntimeWatchdogSec;
  # if the system hard-hangs and the pings stop, the chip resets the board. N100 /
  # industrial boards expose iTCO_wdt; it's a harmless no-op where no watchdog
  # device exists (e.g. a VMware guest). RebootWatchdogSec also arms the watchdog
  # during shutdown, so even a hung reboot still recovers.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "20s";
    RebootWatchdogSec = "30s";
  };
}
