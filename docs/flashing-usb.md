# Writing the flasher to a USB stick

Turn a flasher artifact (downloaded and reassembled from
[Releases](../README.md#getting-the-flasher), or built per
[building.md](building.md)) into a bootable USB installer.

You need a USB stick of at least **8 GB** for the `.img` (it ships with slack
that the stick's first boot reclaims) or **4 GB** for the `.iso`.
**Everything on it will be erased.**

## Which artifact?

- **`mfd-kiosk-flasher-usb.img` — recommended for physical hardware.** A real
  GPT disk image: FAT32 EFI System Partition with the loader at
  `/EFI/BOOT/BOOTX64.EFI`, plus the flasher root. The stick ends up as a
  completely ordinary GPT/UEFI disk — no isohybrid tricks — which is what
  finicky Aptio-class firmware (e.g. the MeLE PCG02 compute stick) needs.
- **`mfd-kiosk-flasher.iso`** — for VMs (attach as a CD) and optical media. It
  is a hybrid ISO that also boots as USB on most firmware, but some UEFI
  implementations refuse the hybrid layout; if a stick made from the ISO never
  shows up in the boot menu, use the `.img` instead.

Either way the file must be written **raw** (byte-for-byte, "dd mode"). The
`.img` already contains its GPT partition table — do **not** partition or
format the stick first; the tool only copies bytes. Tools that instead extract
files onto a FAT filesystem break the boot.

## balenaEtcher (Windows / macOS / Linux — recommended)

1. Download [balenaEtcher](https://etcher.balena.io/).
2. **Flash from file** → select `mfd-kiosk-flasher-usb.img` (or the `.iso`).
3. **Select target** → pick the USB stick.
4. **Flash.** Etcher writes the image raw and verifies it afterwards
   automatically.

## Rufus (Windows)

1. Download [Rufus](https://rufus.ie/).
2. **Device** → the USB stick; **Boot selection** → the flasher file.
3. Click **START**.
   - With `mfd-kiosk-flasher-usb.img` Rufus writes it raw with no questions —
     an `.img` has no "ISO mode".
   - With `mfd-kiosk-flasher.iso`, when Rufus shows the *"ISOHybrid image
     detected"* dialog, choose **Write in DD Image mode** — *not* "ISO Image
     mode". ISO mode re-creates the filesystem and copies files, which breaks
     the boot.
4. Wait for completion and eject.

## dd (Linux / macOS)

```sh
# Triple-check the device — this erases it. On Linux: lsblk. On macOS: diskutil list.
sudo dd if=dist/mfd-kiosk-flasher-usb.img of=/dev/sdX bs=8M conv=fsync status=progress
```

Use the whole device (`/dev/sdX`, not `/dev/sdX1`). On macOS the raw device
(`/dev/rdiskN`) is much faster than `/dev/diskN`.

## First boot of the stick (`.img` only)

On its first boot the stick grows its own root partition to fill the USB drive
(a few extra seconds before the wizard appears). That's normal and happens on
the stick only — the target device is untouched until you confirm the install.

## If the write was bad anyway

The install wizard sha256-verifies the kiosk image on the USB before touching
the target disk, so a corrupt or truncated write fails safely at install time
with a "re-write the installer USB" error rather than producing a broken
device.

Next: boot a machine from the stick — [installing.md](installing.md), or try it
in a VM first with [testing-vmware.md](testing-vmware.md).
