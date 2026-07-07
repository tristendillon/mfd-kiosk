# Building from source

How to build the flasher ISO (and the bare kiosk disk image) from this repo.

> Most users don't need this: prebuilt flasher ISOs are published on the repo's
> Releases page — see [Getting the flasher](../README.md#getting-the-flasher).
> Build from source when you're developing, or when you need to change the
> baked-in defaults or recovery keys (`mfd.kiosk.baseUrl` and friends).

## Prerequisites

- **Nix with flakes enabled**, on an **x86_64-linux** builder. The repo's dev
  container (VS Code: "Reopen in Container") or any WSL2/Linux box with Nix
  works.
- **No KVM/qemu needed.** The disk image is assembled by `systemd-repart`
  directly in the Nix sandbox, so it builds fine inside containers and CI
  runners without `/dev/kvm`.
- ~10 GB of free disk for the Nix store + build scratch. Everything heavy
  (firefox-esr, the kernel) comes prebuilt from `cache.nixos.org`; nothing is
  compiled from source.

If you use the dev container, `direnv` auto-loads the dev shell from the root
`flake.nix` (formatters, linters, `nil` LSP). The dev shell is *not* required to
build — plain `nix` is enough.

## Defaults you can change

Nothing *must* be configured before building — release ISOs are fleet-generic.
A few defaults live in `os/hosts/kiosk/configuration.nix` if you want to change
them:

- `mfd.kiosk.baseUrl` — the default dashboard base URL the install wizard
  offers; Enter accepts it. The per-device token is appended at runtime and
  never stored in the image.
- `mfd.kiosk.adminKeys` — *optional* fleet-wide recovery SSH key(s) for the
  `technician` account. Per-device credentials (password + SSH keys) are
  collected by the install wizard instead, so this can stay empty.
- `mfd.kiosk.rebootTime` — daily reboot time (default `04:00`, local).

The timezone is **not** configured here — it's detected automatically at
runtime by IP geolocation (UTC fallback). Per-device identity (hostname,
dashboard base URL, optional Wi-Fi credentials, technician password, per-device
SSH keys) is collected by the install wizard at flash time and stamped onto the
target disk (see [installing.md](installing.md)).

## Build the flasher ISO

Run from the **repo root**:

```sh
nix run ./os#iso
# -> ./dist/mfd-kiosk-flasher.iso   (git-ignored, ~3 GB)
```

Use `nix run` (not `nix build`) here on purpose: a plain `nix build` only
leaves a read-only `/nix/store` symlink, while the app copies a real,
transferable file into `./dist/` and fails loudly if the copy is truncated
(e.g. disk full) — a short ISO otherwise boots into a confusing Stage-1 error.

The ISO carries the finished, compressed kiosk disk image as a plain file (plus
a sha256), so the flasher never builds anything on the target machine.

### Just the bare disk image

To `dd` the kiosk image straight onto a disk in the lab, skip the ISO:

```sh
nix build ./os#image
# -> result/mfd-kiosk_*.raw.zst
```

### Diagnostic (debug) build for board bring-up

When a board won't come up (blank screen, no SSH, `Ctrl+Alt+F2` dead — common on
quirky hardware like the Cherry Trail Intel Compute Stick), build the **debug**
variant. It flips `mfd.kiosk.debug` on (see `os/modules/debug.nix`): the boot is
un-quieted and a **passwordless `technician` autologin shell is placed on tty1**
— the screen already in front of you — so you can read the boot and inspect the
box (`journalctl -b`, `ip a`, `systemctl status cage-tty1`) with no working
VT-switch, USB keyboard, or dashboard token required.

```sh
nix run   ./os#isoDebug     # -> ./dist/mfd-kiosk-flasher-debug.iso
nix build ./os#imageDebug   # or just the bare debug disk image
```

CI also builds it on demand: run the **Release** workflow via *workflow_dispatch*
and download the `mfd-kiosk-flasher-debug` artifact.

> **Do not deploy the debug image to production or publish it.** Anyone with
> physical access gets a root-capable shell with no password and no token. It is
> never attached to a tagged public release for this reason. Once the board is
> diagnosed, flash the normal production ISO.

## What the build produces

The kiosk image is a **UEFI-only** GPT disk image:

- a 512 MB ESP containing systemd-boot at the removable-media fallback path
  (`/EFI/BOOT/BOOTX64.EFI`) plus a Unified Kernel Image — required because the
  image is flashed offline, so firmware must auto-discover the loader;
- a compact ext4 root (label `nixos`) that **grows to fill the disk on first
  boot**.

There is **no BIOS/legacy boot support** — target machines (and test VMs) must
boot in UEFI mode. The install wizard refuses to run if the flasher itself was
booted via legacy BIOS/CSM.

## Fast checks without a full build

```sh
nix flake check ./os                 # evaluate all outputs
nix eval ./os#nixosConfigurations.kiosk.config.system.build.toplevel.drvPath
```

Both catch Nix-level mistakes in seconds; only boot-level behavior needs a VM
(see [testing-vmware.md](testing-vmware.md)).

## Getting the ISO out of the dev container / WSL

- **VS Code dev container:** right-click `dist/mfd-kiosk-flasher.iso` in the
  Explorer → **Download**.
- **WSL2:** copy from `\\wsl.localhost\<distro>\<path-to-repo>\dist\` in
  Windows Explorer.

Then write it to a USB stick — see [flashing-usb.md](flashing-usb.md).
