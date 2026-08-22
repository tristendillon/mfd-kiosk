# Testing in VMware

End-to-end test of the flasher + kiosk image in a VMware VM (Workstation /
Player / Fusion) before touching real hardware. This mirrors the exact flow a
technician runs on a board.

## VM creation checklist

- **Firmware type: UEFI** — this is the one that bites. VMware defaults new VMs
  to legacy BIOS; the kiosk image is UEFI-only (no BIOS boot code). A BIOS VM
  boots the flasher ISO fine (the ISO is hybrid), flashes fine, and then the
  installed disk is invisible to the firmware: it falls through to PXE and ends
  at *"Operating System not found"*. Set **VM Settings → Options → Advanced →
  Firmware type → UEFI** (or `firmware = "efi"` in the `.vmx`) *when creating
  the VM* — some VMware versions lock the setting after first power-on. The
  install wizard also refuses to run under legacy BIOS with a message pointing
  here.
- **Memory: 2 GB**, to mirror the target boards (the flasher streams the image
  with near-zero RAM, and the kiosk itself is tuned for 2 GB).
- **Disk: ≥ 8 GB**, any controller — SATA, LSI Logic (Parallel/SAS) and
  VMware Paravirtual (PVSCSI) drivers are all baked into the image's initrd.
- **CD/DVD:** attach `dist/mfd-kiosk-flasher.iso`.
- **Network:** NAT or bridged; the kiosk expects DHCP.

## Test flow

1. **Boot the VM.** It comes up as the `mfd-flasher` live environment and
   drops straight into the install wizard on tty1.
2. **Run the wizard** — hostname, dashboard base URL (Enter accepts the
   default), Wi-Fi SSID (leave blank — VMs have no Wi-Fi hardware, so entering
   an SSID now fails fast with "no Wi-Fi adapter detected"), technician
   password, optional SSH keys, pick the virtual disk, type `ERASE`. Full
   walkthrough in [installing.md](installing.md).
3. **Disconnect the ISO** from the VM (the wizard's "remove the USB stick"
   step), then press Enter to reboot.
4. **First boot of the installed image:** the root partition grows to fill the
   virtual disk and the hostname from the wizard is applied. The screen goes
   **intentionally blank** — no token yet, so the browser is held down.
5. **Provision the token:** switch to tty2 (`Ctrl-Alt-F2`; in VMware use
   `Ctrl-Alt-Space` then `Ctrl-Alt-F2`, or the on-screen keyboard menu), log in
   as `technician` with the wizard password — you're auto-prompted for the
   token (or run `sudo mfd-set-token`). SSH works too if the VM's IP is
   reachable.
6. **Verify:** the dashboard renders fullscreen. `systemctl status cage-tty1`
   should show the browser running with `Restart=always`.

## Testing the raw USB image (`.img`) in a VM

The flow above uses the ISO as a virtual CD — the easiest path. To exercise the
`mfd-kiosk-flasher-usb.img` itself (the artifact recommended for physical
hardware), attach it as a **second disk** instead of a CD:

- **VMware:** convert to VMDK and add it as an existing disk, then pick it in
  the firmware boot menu (Esc at the VMware logo):

  ```sh
  qemu-img convert -f raw -O vmdk dist/mfd-kiosk-flasher-usb.img flasher.vmdk
  ```

- **qemu (works in the dev container, no VMware needed):**

  ```sh
  qemu-img create -f qcow2 target.qcow2 8G
  qemu-system-x86_64 -m 2048 -machine q35 \
    -drive if=pflash,format=raw,readonly=on,file=/path/to/OVMF_CODE.fd \
    -drive file=dist/mfd-kiosk-flasher-usb.img,format=raw \
    -drive file=target.qcow2
  ```

On the image's first boot it grows its own root partition to fill the virtual
disk before the wizard appears — normal. After flashing, power off and detach
the flasher disk before rebooting (the "remove the USB stick" step).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| PXE attempt, then *"Operating System not found"* after install | VM firmware is legacy BIOS. Recreate the VM with UEFI firmware (see checklist). |
| Wizard exits immediately with a "legacy BIOS mode" error | Same as above — the guard working as intended. |
| Blank screen after first boot | Expected until a token is set (step 5). |
| Emergency mode / root not found after the bootloader | Disk controller not in the image's initrd module list (`os/hosts/kiosk/hardware.nix`) — stick to SATA/LSI/PVSCSI. |
| Blank or garbled dashboard rendering | vmwgfx GPU quirk — see the commented software-rendering fallback prefs in `os/modules/browser.nix`. |
