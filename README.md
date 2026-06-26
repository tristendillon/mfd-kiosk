# MFD Kiosk Setup

This repository installs and configures an Ubuntu Server device as a dedicated kiosk for the MFD Alert Dashboard.

---

# Minimum Requirements

## Hardware

Minimum supported hardware:

```text
CPU: 2 cores / 2 vCPU
RAM: 4 GB
Storage: 32 GB SSD/eMMC
Display: 1920×1080
Graphics: Hardware acceleration enabled
Network: Ethernet or Wi-Fi
```

Recommended hardware:

```text
CPU: Intel N100 or better
RAM: 8 GB
Storage: 64 GB SSD
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
git clone <repository-url>
cd kiosk-scripts
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
https://mfd.alertdashboard.com/<TOKEN>?sp&kiosk=1&reducedMotion=1
```

After installation, reboot:

```bash
sudo reboot
```

---

# What the Installer Configures

The installer will:

- Create/configure the `kiosk` display user.
- Install the lightweight GUI stack.
- Configure automatic login.
- Launch Chromium in kiosk mode.
- Save the private dashboard URL locally.
- Disable sleep and screen blanking.
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
- The lightdm, SSH, and Xorg kiosk config drop-ins (and disables lightdm).
- The masked sleep/suspend/hibernate targets (restored to normal).
- The `/etc/mfd-kiosk` token store.
- The `kiosk` user and its home directory.
- The GUI/kiosk packages (lightdm, openbox, unclutter, chromium-browser, xorg, etc.).
- The installed repo at `/opt/mfd-kiosk`.

SSH access is intentionally preserved: `openssh-server`, `git`, `curl`, and
`ca-certificates` are **not** removed, so you can still reach and reinstall the device.

The uninstaller copies itself to `/tmp` and runs from there so it can delete
`/opt/mfd-kiosk`, then removes that temporary copy when it finishes.
