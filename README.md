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

Two flakes on purpose, so the dev tools and the appliance can pin different
nixpkgs:

```
flake.nix              # DEV environment (nixos-unstable + claude-code); what direnv loads
.envrc                 # use flake
.devcontainer/         # VS Code dev container (Debian + single-user Nix)
os/                    # the APPLIANCE flake (pinned stable nixpkgs)
  flake.nix            #   nixosConfigurations.{kiosk,installerIso}; `nix build ./os#iso`
  hosts/kiosk/         #   configuration.nix, hardware.nix, disk.nix
  modules/             #   browser, user, ssh, slim, maintenance, secrets, options, installer
legacy/                # frozen Ubuntu/bash setup, for reference
```

## Develop

Open the repo in the dev container (VS Code: "Reopen in Container"). It builds a
Debian image with single-user Nix, claims the persistent `/nix` volume, and
`direnv` auto-loads the dev shell from the root `flake.nix` (nix linters/
formatter, `nil` LSP, claude-code).

## Build & test the appliance

The appliance is the **`os/`** flake. Edit `os/hosts/kiosk/configuration.nix`
first:

- `mfd.kiosk.adminKeys` — **required**: technician SSH public key(s). SSH is
  key-only; an empty list fails the build by assertion (so you can't lock
  yourself out).
- `mfd.kiosk.baseUrl` — dashboard base URL (token appended at runtime).
- `mfd.kiosk.diskDevice` — default install disk (installer can override).
- `time.timeZone` — confirm for the department.

Build the installer ISO and test it in **VMware** (no qemu in the dev shell):

```sh
nix build ./os#iso
# -> ./result/iso/mfd-kiosk-installer.iso
#    create a VMware VM (UEFI/EFI firmware), attach the ISO, boot, then:
sudo mfd-install      # lists disks -> disko partition -> nixos-install -> token prompt
```

`mfd-install` needs network at install time to fetch the system closure. After
install, the VM boots into cage + cog showing the dashboard.

Measure footprint on the running system (PSS, all child procs):

```sh
smem -t -P 'cog|WPE'
```

Google Maps **performance** is only meaningful on hardware with a real GPU.

## Day-2

- Update a device: `sudo nixos-rebuild switch --flake <repo>/os#kiosk`; it rolls
  back automatically if boot fails.
- Re-set the token: `sudo mfd-set-token`.
- The token lives only in `/etc/mfd-kiosk/kiosk.env` (root:kiosk 0640) — never in
  git or the Nix store.
