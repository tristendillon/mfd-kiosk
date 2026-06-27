# MFD kiosk (NixOS)

Declarative NixOS appliance that boots straight into a fullscreen
[cog](https://github.com/Igalia/cog) (WPE WebKit) kiosk showing the MFD
dashboard. Replaces the previous imperative Ubuntu + bash setup (kept under
`legacy/` for reference).

Targets low-end boards: **2 GB RAM, 8 GB eMMC**. The OS is built as a finished,
compressed **disk image** on a dev box and **flashed** onto the board from a USB
stick — nothing is built on the device, so the 2 GB never has to hold a build.
Devices are immutable and **re-flashed to update**.

## Why this exists

- **Reproducible** — the whole device is one flake; a byte-identical image per board.
- **Lighter** — cog/WPE renders the dashboard in far less RAM than Firefox.
- **Fits 2 GB / 8 GB** — minimal profile, zram, earlyoom, grow-to-fill on first boot.
- **One image, Intel + AMD** — drivers/firmware load by PCI id; no per-board work.

> **nixpkgs pin:** the appliance is pinned to **nixos-25.05**, the last release
> that ships `cog`. cog was removed in 25.11 ("depends on unmaintained
> libraries"); don't bump past 25.05 without replacing the browser first.

## Layout

Two flakes on purpose, so the dev tools and the appliance can pin different
nixpkgs:

```
flake.nix              # DEV environment (nixos-unstable + claude-code); what direnv loads
.envrc                 # use flake
.devcontainer/         # VS Code dev container (Debian + single-user Nix)
os/                    # the APPLIANCE flake (pinned nixos-25.05)
  flake.nix            #   nixosConfigurations.{kiosk,flasherIso}; `.#image`, `nix run ./os#iso`
  hosts/kiosk/         #   configuration.nix, hardware.nix (+ filesystems)
  modules/             #   browser, user, ssh, slim, minimal, image, flasher,
                       #   maintenance, secrets, options
legacy/                # frozen Ubuntu/bash setup, for reference
```

## Develop

Open the repo in the dev container (VS Code: "Reopen in Container"). It builds a
Debian image with single-user Nix, claims the persistent `/nix` volume, and
`direnv` auto-loads the dev shell from the root `flake.nix` (nix linters/
formatter, `nil` LSP, claude-code).

## Configure

The appliance is the **`os/`** flake. Edit `os/hosts/kiosk/configuration.nix`
before building:

- `mfd.kiosk.adminKeys` — **required**: technician SSH public key(s). SSH is
  key-only; an empty list fails the build by assertion (so you can't lock
  yourself out). Generate one on the technician's machine with
  `ssh-keygen -t ed25519` and paste the `.pub` line here.
- `mfd.kiosk.baseUrl` — dashboard base URL (token appended at runtime).
- `time.timeZone` — confirm for the department.

(`mfd.kiosk.diskDevice` is now inert — the image is disk-agnostic and the flasher
prompts for the target disk. It's kept only so old references don't break.)

## Build the flasher USB

The build produces the kiosk **disk image** and bakes it onto a bootable
**flasher ISO** (the USB carries the image; the board never builds anything).
Run from the **repo root** — `nix run` builds it and copies a real, transferable
file to `./dist/` (a plain `nix build` only leaves a `/nix/store` symlink):

```sh
nix run ./os#iso
# -> ./dist/mfd-kiosk-flasher.iso   (git-ignored; carries the prebuilt image)
```

The image build runs `systemd-repart` **in the Nix sandbox — no qemu/KVM
needed**. Want just the bare disk image (e.g. to `dd` directly in the lab)?
`nix build ./os#image` → `result/mfd-kiosk_*.raw.zst`.

> **Heads up — the first build compiles WebKit from source** (cog pulls an
> uncached `webkitgtk_4_0`; ~13 GB peak RAM, 1–2 h). On a memory-limited box it
> will OOM and can take down Docker/WSL unless you cap build parallelism and give
> the VM swap headroom first. **Read [`docs/BUILDING.md`](docs/BUILDING.md)
> before your first build** — it covers the root cause, the one-time env setup,
> the isolated WebKit build, and troubleshooting.

Then move the ISO onto the host: in the dev container, right-click it in the VS
Code explorer → **Download**, or (on WSL) copy from
`\\wsl.localhost\<distro>\...\dist\`. Write it to a USB stick (Rufus / Ventoy /
`dd`).

## Provision a board: USB → eMMC → running kiosk

Same steps on a VM (test in **VMware**) and on real hardware. **No network or
RAM headroom needed at flash time** — the image streams straight to disk.

1. **Boot the board from the USB.** It comes up as the `mfd-flasher` live
   environment (SSH is on, so you can also flash it headless).
2. **Flash the internal disk:**

   ```sh
   sudo mfd-flash
   ```

   It lists disks → prompts for the **internal** target (e.g. `/dev/mmcblk0`) →
   requires typing `ERASE` → streams the image with `zstd -dc | dd` (RAM-free).
3. **Remove the USB and reboot.** On first boot the root partition **grows to
   fill the disk**, the machine comes up as `mfd-kiosk`, auto-logs in the `kiosk`
   user, and renders cog fullscreen on the dashboard.
4. **Set the per-device token.** SSH in as `technician` (key-only) and run:

   ```sh
   sudo mfd-set-token
   ```

   Until then the screen shows a "run `mfd-set-token`" message instead of the
   dashboard — that just means the token isn't provisioned yet.

Measure footprint on the running system (PSS, all child procs):

```sh
smem -t -P 'cog|WPE'
```

Google Maps **performance** is only meaningful on hardware with a real GPU.

## Day-2

- **Update = re-flash.** Rebuild the ISO (`nix run ./os#iso`) and re-provision.
  Devices are immutable; there is no on-device `nixos-rebuild`.
- Re-set the token anytime over SSH: `sudo mfd-set-token`.
- The token lives only in `/etc/mfd-kiosk/kiosk.env` (root:kiosk 0640) — never in
  git or the Nix store.
- Adding/rotating a technician key means rebuilding the image (`adminKeys` are
  baked in) and re-flashing.
