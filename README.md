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

Grab a prebuilt ISO from the repo's **[Releases](../../releases)** page — no
Nix, no build. Because the ISO is ~3 GB and GitHub caps release assets at 2 GiB,
it is published **split** into `mfd-kiosk-flasher.iso.part0`,
`mfd-kiosk-flasher.iso.part1`, … alongside a `SHA256SUMS`. Download every part
plus `SHA256SUMS`, then reassemble:

```sh
# Linux / macOS
cat mfd-kiosk-flasher.iso.part* > mfd-kiosk-flasher.iso
```

```bat
:: Windows (cmd)
copy /b mfd-kiosk-flasher.iso.part0+mfd-kiosk-flasher.iso.part1 mfd-kiosk-flasher.iso
```

Verify before flashing:

```sh
sha256sum -c SHA256SUMS            # Linux / macOS (checks parts + whole ISO)
```

```bat
:: Windows — compare against the mfd-kiosk-flasher.iso line in SHA256SUMS
certutil -hashfile mfd-kiosk-flasher.iso SHA256
```

Then continue at [docs/flashing-usb.md](docs/flashing-usb.md).

> Release ISOs are **fleet-generic** — per-device and per-site settings
> (hostname, dashboard URL, credentials) are collected by the install wizard,
> not baked in. **Building from source**
> ([docs/building.md](docs/building.md)) is the secondary path — for
> development or when you need to change the baked-in defaults or recovery keys.

Maintainers: see [docs/releasing.md](docs/releasing.md) for how CI and the
release pipeline work.

## From zero to a running kiosk

1. **Get** the flasher ISO — download a [release](#getting-the-flasher), or
   build from source ([docs/building.md](docs/building.md))
2. **Write** it to a USB stick with Etcher or Rufus —
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
os/                    # the APPLIANCE flake (pinned nixos-25.11)
  flake.nix            #   nixosConfigurations.{kiosk,flasherIso}; `nix run ./os#iso`, `.#image`
  hosts/kiosk/         #   configuration.nix (site config), hardware.nix (generic HW profile)
  modules/             #   image (repart disk image), flasher (USB installer + wizard),
                       #   browser (cage + firefox-esr), identity (per-device state),
                       #   user, ssh, secrets (token), maintenance, minimal, slim, options
docs/                  # build / flash / install / VM-test guides
```

## Configuration

Release ISOs are fleet-generic: the image needs no per-site editing before
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

## Day-2

- **Update = re-flash.** Rebuild the ISO and re-run the installer; there is no
  on-device `nixos-rebuild`.
- Set or rotate the dashboard token any time: SSH in as `technician`, run
  `sudo mfd-set-token`.
- The token lives only in `/etc/mfd-kiosk/kiosk.env` (root:kiosk 0640) — never
  in git or the Nix store.
- Browser crashes auto-restart; the box reboots itself daily at
  `rebootTime`.
