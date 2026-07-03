# Writing the flasher to a USB stick

Turn `mfd-kiosk-flasher.iso` (downloaded and reassembled from
[Releases](../README.md#getting-the-flasher), or built per
[building.md](building.md)) into a bootable USB installer.

You need a USB stick of at least **4 GB**. **Everything on it will be erased.**

The ISO must be written **raw** (byte-for-byte, "dd mode"). Tools that instead
extract the ISO onto a FAT filesystem break the NixOS live boot.

## balenaEtcher (Windows / macOS / Linux — recommended)

1. Download [balenaEtcher](https://etcher.balena.io/).
2. **Flash from file** → select `mfd-kiosk-flasher.iso`.
3. **Select target** → pick the USB stick.
4. **Flash.** Etcher writes the image raw and verifies it afterwards
   automatically.

## Rufus (Windows)

1. Download [Rufus](https://rufus.ie/).
2. **Device** → the USB stick; **Boot selection** → `mfd-kiosk-flasher.iso`.
3. Click **START**. When Rufus shows the *"ISOHybrid image detected"* dialog,
   choose **Write in DD Image mode** — *not* "ISO Image mode". ISO mode
   re-creates the filesystem and copies files, which breaks the boot.
4. Wait for completion and eject.

## dd (Linux / macOS)

```sh
# Triple-check the device — this erases it. On Linux: lsblk. On macOS: diskutil list.
sudo dd if=dist/mfd-kiosk-flasher.iso of=/dev/sdX bs=8M conv=fsync status=progress
```

Use the whole device (`/dev/sdX`, not `/dev/sdX1`). On macOS the raw device
(`/dev/rdiskN`) is much faster than `/dev/diskN`.

## If the write was bad anyway

The install wizard sha256-verifies the kiosk image on the USB before touching
the target disk, so a corrupt or truncated write fails safely at install time
with a "re-burn the ISO" error rather than producing a broken device.

Next: boot a machine from the stick — [installing.md](installing.md), or try it
in a VM first with [testing-vmware.md](testing-vmware.md).
