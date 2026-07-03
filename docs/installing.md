# Installing on a device

Provisioning a kiosk board (or a VM — the steps are identical, see
[testing-vmware.md](testing-vmware.md)) from the flasher USB created in
[flashing-usb.md](flashing-usb.md).

Nothing is downloaded or built at install time: the USB carries the finished
kiosk image and streams it onto the internal disk, so a 2 GB board with no
network provisions fine.

## 1. Firmware prep (one-time per machine)

- Boot mode must be **UEFI**. Disable CSM / "legacy boot" in the firmware
  setup. The kiosk image has no BIOS boot code — a machine left in legacy mode
  would flash successfully and then fail to boot with *"Operating System not
  found"*. The wizard refuses to run under legacy BIOS for exactly this reason.
- Set **"Restore on AC Power Loss"** (a.k.a. *AC Power Recovery* / *After Power
  Failure* / *State After Power On*, wording varies by vendor) to **Power On**
  (or *Last State*). This is what makes the kiosk turn itself back on after an
  outage — a power blip, or the weekly generator test where mains drops and the
  generator picks up. Left on the common default ("Stay Off"), the board stays
  dark after every power event until someone physically presses the power
  button. **The OS cannot control this** — it is firmware-only, so it must be
  set here, per machine.
- Use the firmware's one-time boot menu (usually F12/F11/Esc) to boot from the
  USB stick, so you don't have to change the permanent boot order.

## 2. Run the install wizard

The stick boots the `mfd-flasher` live environment and lands directly in the
install wizard on tty1 — no login, nothing to type to start it. It walks
through:

1. **Hostname** — the per-device name, e.g. `mfd-fh-05-kiosk`. Lowercase
   letters, digits and hyphens; max 63 chars.
2. **Dashboard base URL** — where the kiosk dashboard lives. Pre-filled with the
   baked-in default; press Enter to accept it, or type a different URL.
3. **Wi-Fi (optional)** — leave the SSID blank for wired ethernet (the default,
   and preferred when both are available); or enter the SSID and WPA2 passphrase
   of the device network. If you enter an SSID, the passphrase (8–63 chars) is
   asked twice with hidden input. The wizard then **verifies the credentials
   against the real hardware**: it checks the machine actually has a Wi-Fi
   adapter (if not, it says so — the kiosk can only use wired ethernet) and
   actually connects to the network before accepting them. A failed test
   (no adapter, network not found, or wrong passphrase) loops back to the SSID
   prompt so you can retype it or leave it blank to skip Wi-Fi.
4. **Technician password** — for the `technician` account (local console tty2+
   and SSH).
5. **SSH keys (optional)** — per-device public keys for `technician`; paste one
   per line, empty line to finish/skip.
6. **Target disk** — internal disks are listed with the installer USB
   automatically excluded; the largest internal disk (e.g. `/dev/mmcblk0`) is
   preselected.
7. **Confirmation** — type `ERASE`. All data on the target disk is destroyed.

The wizard then sha256-verifies the image on the USB, streams it onto the disk
(`zstd -dc | dd` — near-zero RAM), and stamps the per-device identity onto the
flashed root partition under `/var/lib/mfd/` (Wi-Fi credentials, if any, land at
`/var/lib/iwd/<ssid>.psk` in iwd's native format). The image itself is
byte-identical for every device; only this stamp differs.

If anything fails, the wizard prints the error, waits for Enter, and restarts
fresh — aborting is always safe before you type `ERASE`.

### Headless install (optional)

The live flasher runs sshd with root login for the fleet recovery key(s) baked
into `mfd.kiosk.adminKeys`. SSH in and run the same wizard remotely:

```sh
ssh root@<flasher-ip>   # key from mfd.kiosk.adminKeys
mfd-install
```

## 3. First boot

Remove the USB when the wizard says so, press Enter to reboot. On first boot
the machine:

- grows the root partition + filesystem to fill the disk;
- applies the hostname from the wizard (before DHCP, so the lease shows the
  real name);
- detects its timezone automatically via IP geolocation (best effort, falling
  back to UTC when offline or undetectable);
- comes up with an **intentionally blank screen** — the kiosk browser stays
  down until a dashboard token is set.

### Networking

Wired ethernet is the default and needs no configuration — plug it in and DHCP
does the rest. If you supplied Wi-Fi credentials in the wizard, the radio comes
up automatically; when both links are connected **ethernet wins** (wired routes
get a lower metric), so a cable always takes over from Wi-Fi.

Wi-Fi must be **WPA2-PSK** — ask IT for an IoT/device SSID on its own VLAN.
SSO/captive-portal networks (e.g. Duo-protected corporate Wi-Fi) and guest
portals can't work on a headless appliance; enterprise 802.1X is possible in
principle but not implemented. You can add, change, or fix Wi-Fi later from a
`technician` shell with `sudo iwctl` (see day-2 below).

## 4. Set the dashboard token

Log in as `technician` (tty2+, or SSH with the wizard password/keys). An
interactive login on an unprovisioned kiosk auto-prompts for the token; it can
also be run any time:

```sh
sudo mfd-set-token
```

The token is appended to the base URL chosen in the wizard and written to
`/etc/mfd-kiosk/kiosk.env` (root:kiosk, 0640) — never into git or the Nix
store. The browser starts the moment the token file appears, and the dashboard
renders fullscreen.

## Day-2 operations

- **Updating = re-flashing.** Devices are immutable; there is no on-device
  `nixos-rebuild`. Rebuild the ISO, boot the stick, re-run the wizard.
- **Rotate the token** any time with `sudo mfd-set-token` (restarts the
  browser).
- **Manage Wi-Fi** interactively with `sudo iwctl` from the console (tty2+) or
  SSH — add a network, swap credentials, or drop one. Changes persist under
  `/var/lib/iwd`.
- **Recovery paths:** local login on tty2+ as `technician`; SSH with the
  per-device keys or password; or the baked `adminKeys` if any were configured
  at build time. Root SSH and the `kiosk` display user are always denied.
- The machine reboots itself daily at `mfd.kiosk.rebootTime` (default 04:00,
  i.e. 4 AM local time).

### Power loss & auto-recovery

The kiosk is built to come back on its own, unattended, after any of these:

- **Power restored after an outage** (blip, or the weekly generator test) — the
  board powers on **only if** the firmware's *Restore on AC Power Loss* is set to
  Power On (see [Firmware prep](#1-firmware-prep-one-time-per-machine)); then it
  boots straight to the dashboard with no keypress. There is no boot menu to wait
  on and no login to type — the token is already stamped, so the browser starts
  automatically.
- **Browser crash** — the compositor restarts it within ~2s, and never gives up
  no matter how fast it crash-loops.
- **A tab exhausts RAM** — the worst offender is killed (earlyoom) and the
  browser restarts, rather than the whole box stalling.
- **Kernel panic / total system hang** — the machine reboots itself: a panic
  reboots after 10s, and a hardware watchdog resets the board if it wedges
  entirely.
- **Nightly hygiene** — a clean reboot at `mfd.kiosk.rebootTime`.

An **unclean** power-off (yanking mains mid-write) is expected and safe: the
root filesystem journals and repairs automatically on the next boot, and the
kiosk writes very little at runtime. Note a *flickering* supply (rapid off/on/off
during a rough generator transfer) is harder on the hardware than a clean
off-then-on — that's a firmware/power concern, not something the OS can smooth
over.

To rehearse this in a VM, **hard power-off** the guest (not a graceful shutdown)
and power it back on: it should boot straight to the dashboard. The AC-recovery
behavior itself is real-hardware-only (a VM has no "AC" to lose).
