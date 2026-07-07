{ config, lib, ... }:

# Diagnostic bring-up mode, gated on `mfd.kiosk.debug` (options.nix; default
# off). Purpose: on a board this image was never tested against (the Cherry
# Trail Intel Compute Stick), we're blind — the boot is `quiet`, tty1 is
# intentionally left blank until a dashboard token exists (browser.nix disables
# getty@tty1/autovt@tty1 and gates cage on the token), and Ctrl+Alt+F2 relies on
# a working i915 console + USB keyboard, both flaky on Cherry Trail. This module
# gives an autologin shell RIGHT ON tty1 (the screen already in front of you),
# needing no VT-switch, no keyboard gymnastics, and no token — so you can read
# the boot and inspect the box (`journalctl -b`, `ip a`, `systemctl status
# cage-tty1`) to tell "booted fine, just unprovisioned" apart from a genuine
# Cherry Trail hang.
#
# The un-quiet kernel params (loglevel=7) live in perf.nix, which is debug-aware
# so it can keep the Cherry Trail stability param (intel_idle.max_cstate=1)
# active here too — a debug boot that itself froze would tell us nothing.
let
  cfg = config.mfd.kiosk;
in
{
  config = lib.mkIf cfg.debug {
    # Re-enable the tty1 getty that browser.nix turns off, and autologin the
    # technician so a shell appears with no password. cage stays condition-blocked
    # while there's no token, so nothing else is contending for tty1 in this mode.
    # mkForce beats browser.nix's plain `enable = false`.
    systemd.services."getty@tty1".enable = lib.mkForce true;
    services.getty.autologinUser = lib.mkForce cfg.adminUser;

    # Un-quiet the console. perf.nix already drops the `quiet`/`loglevel=3`
    # cluster in debug mode; consoleLogLevel is the knob that sets the trailing
    # `loglevel=` NixOS appends (default 4 = warnings+), and the kernel honors the
    # LAST loglevel, so this is what actually raises it. 7 = show everything.
    boot.consoleLogLevel = lib.mkForce 7;

    # Show every unit as it starts (perf.nix's systemd.show_status=auto is dropped
    # in debug mode) so a stall is visible on-screen, not hidden behind a tidy boot.
    boot.kernelParams = [ "systemd.show_status=true" ];
  };
}
