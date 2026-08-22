# MFD kiosk (NixOS)

Declarative NixOS appliance that boots straight into a fullscreen
**firefox-esr** kiosk (under the [cage](https://github.com/cage-kiosk/cage)
Wayland compositor) showing the MFD dashboard. Replaces the previous imperative
Ubuntu + bash setup.

Targets low-end boards: **2 GB RAM, 8 GB eMMC**. The OS is built as a finished,
compressed **disk image** on a dev box and streamed onto the board by a USB
**flasher** — nothing builds or downloads on the device. Devices are immutable
and **re-flashed to update**; the only per-device state (hostname, technician
credentials, dashboard token, optional Wi-Fi credentials) lives outside the
image.

## Getting the flasher

Grab a prebuilt flasher from the repo's **[Releases](../../releases)** page —
no Nix, no build. Two artifacts are published:

| Artifact | Use it for |
|---|---|
| `mfd-kiosk-flasher-usb.img` | **Physical hardware (recommended).** A real GPT disk image (FAT32 EFI System Partition + root) written byte-for-byte to the stick. Some UEFI firmwares — e.g. the MeLE PCG02's Aptio — refuse the isohybrid ISO layout; this image is what they boot. |
| `mfd-kiosk-flasher.iso` | VMs (attach as a CD) and optical media. Also boots as USB on most, but not all, firmware. |

Both are ~3 GB and GitHub caps release assets at 2 GiB, so each is published
**split** into `.part0`, `.part1`, … alongside a `SHA256SUMS`. Download every
part of the artifact you want plus `SHA256SUMS`, then reassemble (same pattern
for the `.iso`):

```sh
# Linux / macOS
cat mfd-kiosk-flasher-usb.img.part* > mfd-kiosk-flasher-usb.img
```

```bat
:: Windows (cmd)
copy /b mfd-kiosk-flasher-usb.img.part0+mfd-kiosk-flasher-usb.img.part1 mfd-kiosk-flasher-usb.img
```

Verify before flashing:

```sh
sha256sum -c SHA256SUMS            # Linux / macOS (checks parts + whole images)
```

```bat
:: Windows — compare against the matching line in SHA256SUMS
certutil -hashfile mfd-kiosk-flasher-usb.img SHA256
```

Then continue at [docs/flashing-usb.md](docs/flashing-usb.md).

> Release flashers are **fleet-generic** — per-device and per-site settings
> (hostname, dashboard URL, credentials) are collected by the install wizard,
> not baked in. **Building from source**
> ([docs/building.md](docs/building.md)) is the secondary path — for
> development or when you need to change the baked-in defaults or recovery keys.

Maintainers: see [docs/releasing.md](docs/releasing.md) for how CI and the
release pipeline work.

## From zero to a running kiosk

1. **Get** the flasher — download a [release](#getting-the-flasher) (the
   `-usb.img` for real hardware, the `.iso` for VMs), or build from source
   ([docs/building.md](docs/building.md))
2. **Write** it to a USB stick with Etcher, Rufus, or `dd` —
   [docs/flashing-usb.md](docs/flashing-usb.md)
3. **Install** on the device: boot the stick, answer the wizard, set the
   dashboard token — [docs/installing.md](docs/installing.md)
4. Or rehearse the whole flow in a VM first —
   [docs/testing-vmware.md](docs/testing-vmware.md)

> The image is **UEFI-only**. Targets (and test VMs) must boot in UEFI mode
> with CSM/legacy disabled — the docs above call this out where it matters.

## Repo layout

Two flakes on purpose, so the dev tools and the appliance pin different
nixpkgs:

```
flake.nix              # DEV environment (nixos-unstable); what direnv loads
.devcontainer/         # VS Code dev container (Debian + single-user Nix)
os/                    # the APPLIANCE flake (pinned nixos-26.05)
  flake.nix            #   nixosConfigurations.{kiosk,flasherIso,flasherUsb}; `nix run ./os#iso`, `.#usb`, `.#image`
  hosts/kiosk/         #   configuration.nix (site config), hardware.nix (generic HW profile)
  modules/             #   image (repart disk image), flasher-common/-iso/-usb (installer + wizard),
                       #   browser (cage + firefox-esr), identity (per-device state),
                       #   user, ssh, secrets (token), maintenance, minimal, slim, options
docs/                  # build / flash / install / VM-test guides
```

## Configuration

Release flashers are fleet-generic: the image needs no per-site editing before
building. A few defaults still live in `os/hosts/kiosk/configuration.nix`:

- `mfd.kiosk.baseUrl` — the default dashboard base URL the wizard offers
  (default `https://mfd.alertdashboard.com`); the installer pre-fills it and
  Enter accepts. The per-device token is appended at runtime, never stored in
  the image.
- `mfd.kiosk.adminKeys` — optional fleet-wide recovery SSH key(s) for the
  `technician` account. The only remaining baked-in site knob worth setting.
- `mfd.kiosk.rebootTime` — daily reboot time (default `04:00`, meaning 4 AM
  local).
- **Timezone** is not configured anywhere — it's detected automatically at boot
  by IP geolocation (best effort), falling back to UTC when offline.

Per-device settings (hostname, dashboard base URL, optional Wi-Fi credentials,
technician password, SSH keys) are collected by the **install wizard** at flash
time, not in the flake — one image serves the whole fleet.

Connectivity is wired ethernet by default; the wizard can also collect an
optional per-device WPA2 Wi-Fi network (ethernet is preferred when both are up).
Details in [docs/installing.md](docs/installing.md).
