# MFD kiosk (NixOS)

Declarative NixOS appliance that boots straight into a fullscreen
[cog](https://github.com/Igalia/cog) (WPE WebKit) kiosk showing the MFD
dashboard. Replaces the previous imperative Ubuntu + bash setup (kept under
`legacy/` for reference).

## Why this exists

- **Reproducible & rollbackable** — the whole device is one flake; atomic
  upgrades and rollback. No install-order bugs, chmod drift, or apt-repo guards.
- **Lighter** — cog/WPE renders the dashboard in far less RAM than Firefox.
- **One image, Intel + AMD** — drivers/firmware load by PCI id; no per-board work.

## Layout

```
flake.nix              # inputs (nixpkgs, disko); nixosConfigurations.{kiosk,installerIso}
hosts/kiosk/
  configuration.nix    # site config: baseUrl, admin SSH keys, disk, timezone
  hardware.nix         # generic profile so one image boots varied boards
  disk.nix             # disko: GPT, 512M ESP + ext4 root
modules/
  options.nix          # the mfd.kiosk.* option set
  browser.nix          # cage + cog kiosk service (the core)
  user.nix             # display-only kiosk user + admin user
  ssh.nix              # key-only admin SSH; kiosk denied; no root
  slim.nix             # zram, journald cap, doc/firmware trims
  maintenance.nix      # daily reboot timer
  secrets.nix          # mfd-set-token (token kept out of the store)
  installer.nix        # installer ISO + mfd-install
```

## Before you build

Edit `hosts/kiosk/configuration.nix`:

- `mfd.kiosk.adminKeys` — **required**: the technician's SSH public key(s).
  (SSH is key-only; an empty list fails the build by assertion.)
- `mfd.kiosk.baseUrl` — dashboard base URL (token appended at runtime).
- `mfd.kiosk.diskDevice` — default install disk (the installer can override).
- `time.timeZone` — confirm for the department.

## Build & test in a VM

```sh
nixos-rebuild build-vm --flake .#kiosk
./result/bin/run-*-vm          # opens a QEMU window
# in the VM, provision a test token then let cage restart:
sudo mfd-set-token
```

Measure footprint inside the VM (PSS, all child procs):

```sh
smem -t -P 'cog|WPE'
```

Maps **performance** is only meaningful on real hardware (the VM has no GPU).

## Build the installer ISO

```sh
nix build .#iso
# -> ./result/iso/mfd-kiosk-installer.iso  ; write to USB, boot the target, run:
sudo mfd-install
```

`mfd-install` lists disks, partitions the chosen one with disko, installs the
flake, and prompts for this device's dashboard token. Needs network at install
time to fetch the system closure.

## Day-2

- Update a device: `sudo nixos-rebuild switch --flake github:.../kiosk#kiosk`
  (or from a local checkout), then it rolls back automatically if boot fails.
- Re-set the token: `sudo mfd-set-token`.
- The token lives only in `/etc/mfd-kiosk/kiosk.env` (root:kiosk 0640) — never in
  git or the Nix store.
