# MFD Kiosk Setup

This repository installs and configures an Ubuntu Server device as a dedicated kiosk for the MFD Alert Dashboard.

---

# Minimum Requirements

## Hardware

Minimum supported hardware:

```text
CPU: 2 cores / 2 vCPU
RAM: 4 GB
Storage: 16 GB SSD/eMMC
Display: 1920×1080
Graphics: Hardware acceleration enabled
Network: Ethernet or Wi-Fi
```

Recommended hardware:

```text
CPU: Intel N100 or better
RAM: 4 GB
Storage: 32 GB SSD
Network: Ethernet preferred
```

Example devices:

- Dell Wyse 5070
- HP t640
- Lenovo Tiny M-series
- Intel N100 mini PC
- Similar x86 thin client or mini PC

---

# Network Requirements

The kiosk requires network access during setup and normal operation.

Ethernet is preferred when available because it is more reliable and easier to support. If the device supports Power over Ethernet through a PoE adapter or dock, Ethernet is the preferred deployment option.

Wi-Fi is supported, but the Wi-Fi adapter must be detected by Ubuntu Server during installation.

## Preferred: Ethernet

For Ethernet installs:

1. Connect Ethernet before starting the Ubuntu Server installer.
2. Allow Ubuntu to use DHCP.
3. Enable OpenSSH Server during installation.
4. After installation, SSH into the device and run the kiosk installer.

Example:

# Install:

```text
Ubuntu Server 26.04
Minimized installation
OpenSSH Server enabled
```

During Ubuntu setup:

1. Select **minimized installation**.
2. Enable **OpenSSH Server**.
3. Create the admin/maintenance user, usually:

```text
technician
```

Do not create or use the `kiosk` user manually. The installer creates and configures the `kiosk` user automatically.

---

# Fresh Installation

Log in as the admin user:

```bash
ssh technician@<device-ip>
```

Update Ubuntu:

```bash
sudo apt update
sudo apt upgrade -y
```

Install Git:

```bash
sudo apt install -y git
```

Clone the repository:

```bash
git clone https://github.com/tristendillon/mfd-kiosk
cd mfd-kiosk
```

Make the scripts executable:

```bash
chmod +x install.sh scripts/*.sh
```

Run the installer:

```bash
sudo ./install.sh
```

The installer will ask for the private dashboard token:

```text
Dashboard token:
```

Input is hidden while typing.

Enter only the private token, not the full URL.

The installer builds the kiosk URL like this:

```text
https://mfd.alertdashboard.com/<TOKEN>
```

Reduced motion is applied by the browser profile (`ui.prefersReducedMotion`),
so no query string is appended to the URL.

After installation, reboot:

```bash
sudo reboot
```

---

# Local Keyboard Access (No SSH)

If you cannot SSH into the device, you can still reach it with a keyboard
connected directly to the kiosk.

The kiosk GUI runs as the display-only `kiosk` user, which is intentionally
blocked from SSH and should **not** be used for maintenance. To update or
configure the device, switch to a text console and log in as the
administrative `technician` user instead.

Switch to a virtual terminal:

```text
Ctrl + Alt + F2
```

Log in as `technician`, then run the update, configuration, or uninstall
steps in the relevant sections below.

When finished, return to the kiosk GUI with:

```text
Ctrl + Alt + F1
```

The kiosk GUI runs on virtual terminal 1 (`tty1`): the `kiosk` user autologs
in there and starts the display directly with `startx` (there is no display
manager). Switch to `tty2` for the `technician` console, and back to `tty1`
for the running display.

Rebooting also brings the device straight back into the kiosk GUI:

```bash
sudo reboot
```

On VMware, the host may intercept these shortcuts. Send them through the
VMware menu instead:

```text
VM → Send Key → Ctrl+Alt+F2
```

---

# Configuration: Setting a Different Admin User

By default the installer keeps the existing administrative/maintenance user
(normally `technician`) and only creates the display-only `kiosk` user. It
detects the admin user automatically from whoever ran `sudo`. If you need to
pin a specific admin user instead, set `KIOSK_ADMIN_USER` in `config.env`.

A minimized Ubuntu Server install ships **without a text editor** (`nano`,
`vi`, and `vim` are all absent), and we intentionally do not install extra
packages. Use `sed`, which is always present, to edit the value in place.

Go to the repo (`/opt/mfd-kiosk` after the first install, or the cloned
directory on a fresh setup):

```bash
cd /opt/mfd-kiosk
```

Set the admin user (replace `newadmin` with the real username, which must
already exist and be in the `sudo` group):

```bash
sudo sed -i 's/^KIOSK_ADMIN_USER=.*/KIOSK_ADMIN_USER="newadmin"/' config.env
```

Confirm the change:

```bash
grep KIOSK_ADMIN_USER config.env
```

Then re-run the installer to apply it:

```bash
sudo ./install.sh
```

The same approach works for any other value in `config.env` (for example
`REBOOT_TIME` or `KIOSK_QUERY`); just change the key name in the `sed`
pattern.

---

# What the Installer Configures

The installer will:

- Create/configure the `kiosk` display user.
- Install a minimal X stack (no display manager): `xserver-xorg-core` + `openbox`,
  started by tty autologin + `startx`.
- Install Firefox ESR from Mozilla's apt repo as a real `.deb` (no Snap), and
  purge `snapd` so nothing pulls it back in.
- Configure automatic login on `tty1`.
- Launch Firefox ESR in kiosk mode with a locked-down system policy and a
  throwaway profile rebuilt on tmpfs each session (no persistent cache/history).
- Save the private dashboard URL locally.
- Disable sleep and screen blanking.
- Add compressed RAM swap (zram) and cap journald disk usage.
- Configure daily reboot.
- Configure browser health checks.
- Block SSH access for the `kiosk` user.
- Move the installer repo to:

```text
/opt/mfd-kiosk
```

After installation, use `/opt/mfd-kiosk` as the permanent repo location.

---

# Updating Existing Devices

SSH into the device as the admin user:

```bash
ssh technician@<device-ip>
```

Go to the installed repo:

```bash
cd /opt/mfd-kiosk
```

Pull the latest changes:

```bash
git pull
```

Make sure scripts are executable:

```bash
chmod +x install.sh scripts/*.sh
```

Run the installer again:

```bash
sudo ./install.sh
```

Enter the dashboard token when prompted.

Reboot:

```bash
sudo reboot
```

The installer is designed to be safe to run multiple times.

---

# Uninstalling

To completely remove the kiosk from a device, run the uninstaller as the admin user:

```bash
sudo /opt/mfd-kiosk/uninstall.sh
```

If the script is not executable, make it executable first:

```bash
chmod +x /opt/mfd-kiosk/uninstall.sh
```

You will be asked to type `yes` to confirm. Pass `--yes` to skip the prompt for
scripted runs:

```bash
sudo /opt/mfd-kiosk/uninstall.sh --yes
```

The uninstaller removes:

- The `mfd-daily-reboot` and `mfd-browser-healthcheck` systemd units.
- The `tty1` autologin override, the SSH, Xorg, and `Xwrapper.config` drop-ins.
- The Firefox policy, the Mozilla apt repo/key/pin, and the `snapd` pin.
- The zram and journald drop-ins.
- The masked sleep/suspend/hibernate targets and masked daemons (restored to normal).
- The `/etc/mfd-kiosk` token/profile store.
- The `kiosk` user and its home directory.
- The GUI/kiosk packages (openbox, firefox-esr, xserver-xorg-\*, fonts-dejavu-core,
  systemd-zram-generator, etc.).
- The installed repo at `/opt/mfd-kiosk`.

Note: `snapd` is purged during install; the uninstaller does not reinstall it.

SSH access is intentionally preserved: `openssh-server`, `git`, `curl`, and
`ca-certificates` are **not** removed, so you can still reach and reinstall the device.

The uninstaller copies itself to `/tmp` and runs from there so it can delete
`/opt/mfd-kiosk`, then removes that temporary copy when it finishes.
