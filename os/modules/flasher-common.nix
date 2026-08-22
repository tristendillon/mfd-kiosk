{ self, config, pkgs, lib, kioskAttr ? "kiosk", ... }:

# Installer live environment shared by both flasher media — the hybrid ISO
# (flasher-iso.nix) and the raw GPT USB image (flasher-usb.nix). Boots straight
# into an interactive wizard on tty1 (no login, no command to type) that
# collects the per-device identity (hostname, dashboard base URL, optional
# Wi-Fi credentials — validated live against real hardware before they're
# accepted, technician password, optional SSH keys), streams the prebuilt
# compressed kiosk image onto the chosen internal disk with `zstd -dc | dd`
# (copying bytes needs almost no RAM, so 2 GB boards provision fine), then
# stamps the identity onto the flashed root partition for the image to pick up
# on first boot (see identity.nix / user.nix / ssh.nix).
#
# Media differences are isolated behind two options:
#   mfd.flasher.payloadDir     — where the payload lives at RUNTIME (a string,
#                                never a store path — see the option comment)
#   mfd.flasher.payloadPackage — the derivation each medium embeds at BUILD time
let
  # Which kiosk image this flasher carries: "kiosk" (production) or "kioskDebug"
  # (the diagnostic variant). Passed from flake.nix via specialArgs so the same
  # modules build all flasher variants. See mkFlasher there.
  kiosk = self.nixosConfigurations.${kioskAttr}.config;
  # The finished kiosk disk image (a dir containing mfd-kiosk_<ver>.raw.zst),
  # built without qemu via systemd-repart. See image.nix.
  kioskImage = kiosk.system.build.image;

  # Interpolate the kiosk's own option values so flasher and image can't drift
  # on paths/usernames.
  stateDir = kiosk.mfd.kiosk.stateDir;
  adminUser = kiosk.mfd.kiosk.adminUser;
  # Default dashboard base URL offered by the wizard; the effective per-device
  # value is stamped to ${stateDir}/base-url and read at token-set time.
  baseUrl = kiosk.mfd.kiosk.baseUrl;

  # The image + a checksum under STABLE names, copied out so each medium can
  # carry them OUTSIDE the flasher's own store closure (isoImage.contents on
  # the ISO, repart CopyFiles on the USB image) instead of letting the multi-GB
  # blob land inside nix-store.squashfs / the store-bearing root fs. Keeping
  # the boot-critical store small (just the flasher's own closure) is what
  # makes Stage 1 survive a truncated medium — the store mount no longer has to
  # read into the image tail. The checksum lets the wizard refuse a corrupt
  # medium.
  kioskFlash = pkgs.runCommand "mfd-kiosk-flash" { } ''
    mkdir -p "$out"
    f=("${kioskImage}"/*.raw.zst)
    cp "''${f[0]}" "$out/mfd-kiosk.raw.zst"
    ( cd "$out" && sha256sum mfd-kiosk.raw.zst > mfd-kiosk.raw.zst.sha256 )
  '';

  # Runtime location of the payload. A plain string on purpose: interpolating
  # it into the wizard script must NOT create a store reference, or the payload
  # would be dragged into the flasher's closure (and duplicated on the medium).
  payloadDir = config.mfd.flasher.payloadDir;

  mfdInstall = pkgs.writeShellApplication {
    name = "mfd-install";
    # iwd provides iwctl, used to live-test Wi-Fi credentials in step 3 (same
    # stack the installed kiosk runs). util-linux provides rfkill.
    runtimeInputs = with pkgs; [ util-linux coreutils gawk gnugrep zstd mkpasswd openssh systemd iwd ];
    text = ''
      #!/usr/bin/env bash
      img="${payloadDir}/mfd-kiosk.raw.zst"

      # On failure, wait for an acknowledgement; the systemd unit has
      # Restart=always, so exiting redraws a fresh wizard on tty1.
      die_pause() {
        echo >&2
        echo "ERROR: $*" >&2
        read -rp "Press Enter to restart the installer... "
        exit 1
      }

      if [ ! -r "$img" ]; then
        die_pause "No image found at $img (is this the flasher USB?)"
      fi

      printf '\033[2J\033[H'
      echo "======================================"
      echo "        MFD kiosk installer"
      echo "======================================"
      echo

      # The kiosk image is UEFI-only (GPT + UKI at the removable-media path; no
      # MBR boot code — see image.nix). The flasher ISO itself is hybrid, so it
      # happily boots under legacy BIOS/CSM — and would then flash a disk this
      # firmware cannot boot ("Operating System not found"). Refuse up front.
      # (The USB-image flasher is UEFI-only too, so this never trips there.)
      if [ ! -d /sys/firmware/efi ]; then
        die_pause "This machine booted in legacy BIOS mode, but the kiosk image only boots via UEFI.
Enable UEFI boot (disable CSM/legacy) in the firmware setup and boot this installer again.
In VMware: VM Settings > Options > Advanced > Firmware type > UEFI."
      fi

      # ---- 1. hostname ------------------------------------------------------
      while :; do
        read -rp "Hostname for this kiosk (e.g. mfd-fh-05-kiosk): " host
        host="''${host,,}"
        if [[ "$host" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
          break
        fi
        echo "Invalid: lowercase letters, digits and hyphens only; no leading/trailing hyphen; max 63 chars."
      done

      # ---- 2. dashboard base URL (default: baked value) ----------------------
      echo
      while :; do
        read -rp "Dashboard base URL [${baseUrl}]: " baseurl
        baseurl="''${baseurl:-${baseUrl}}"
        if [[ "$baseurl" =~ ^https?://[^[:space:]]+$ ]]; then
          # Strip a single trailing slash (token is appended at runtime).
          baseurl="''${baseurl%/}"
          break
        fi
        echo "Invalid: must look like http(s)://host/path with no spaces."
      done

      # ---- 3. Wi-Fi credentials (optional, live-validated) -------------------
      # Blank SSID skips Wi-Fi entirely; the kiosk runs ethernet-only and its
      # radio stays idle (no /var/lib/iwd profile is stamped).
      #
      # A non-blank SSID is validated against real hardware before it's
      # accepted: we detect a wireless adapter, then actually scan for and
      # associate with the network using iwd (iwctl) — the same stack the kiosk
      # runs — so a machine with no Wi-Fi card, an out-of-range/mistyped SSID,
      # or a wrong passphrase is caught HERE instead of silently failing after
      # install. This whole step is a retry loop; every path except "connected"
      # and "blank" returns to the SSID prompt, and a blank SSID always escapes.
      #
      # The script runs under `set -euo pipefail`, so every iwctl call (which
      # can exit nonzero for transient reasons) is guarded with `|| true` or an
      # `if`, and every wait has an explicit timeout so tty1 can't hang. The
      # passphrase is passed via --passphrase and never printed in any message.
      echo
      # On the USB-image flasher /var/lib/iwd is persistent ext4 (the ISO's
      # lives on the tmpfs live root), so an aborted earlier run — power cut
      # between "connected" and "forget" — could leave a stale profile behind,
      # and the success path below captures /var/lib/iwd/*.psk by glob. Start
      # clean.
      rm -f /var/lib/iwd/*.psk 2>/dev/null || true
      wifi_ssid=""
      wifi_pass=""
      wifi_prev=""
      wifi_file=""
      wifi_profile=""
      while :; do
        if [ -n "$wifi_prev" ]; then
          # Prefill the last attempt so the user can fix a typo (or clear it to skip).
          read -e -i "$wifi_prev" -rp "Wi-Fi SSID (blank = wired ethernet only): " wifi_ssid
        else
          read -rp "Wi-Fi SSID (blank = wired ethernet only): " wifi_ssid
        fi
        wifi_prev=""
        if [ -z "$wifi_ssid" ]; then
          break                                   # blank -> wired ethernet only
        fi
        if [ "''${#wifi_ssid}" -gt 32 ]; then
          echo "Wi-Fi SSID must be 1-32 bytes — try again (or blank to skip)."
          continue
        fi

        # Detect a wireless adapter. Clear any soft rfkill block first, else a
        # present card can look absent.
        rfkill unblock wifi || true
        shopt -s nullglob
        wifi_devs=(/sys/class/net/*/wireless)
        shopt -u nullglob
        if [ "''${#wifi_devs[@]}" -eq 0 ]; then
          echo "No Wi-Fi adapter detected on this machine — this kiosk can only use wired ethernet."
          echo "Leave the SSID blank to continue with wired ethernet only."
          continue
        fi
        # /sys/class/net/<dev>/wireless -> <dev>
        dev="$(basename "$(dirname "''${wifi_devs[0]}")")"

        echo "Set the Wi-Fi passphrase (WPA2-PSK, 8-63 characters)."
        while :; do
          read -rsp "Passphrase: " w1; echo
          read -rsp "Confirm:    " w2; echo
          if [ "$w1" != "$w2" ]; then
            echo "Mismatched — try again."
          elif [ "''${#w1}" -lt 8 ] || [ "''${#w1}" -gt 63 ]; then
            echo "Passphrase must be 8-63 characters — try again."
          else
            break
          fi
        done
        wifi_pass="$w1"

        echo ">> Testing Wi-Fi on $dev ..."

        # (a) Wait for iwd to claim the interface (it may need a moment at boot).
        if_ready=""
        for _ in $(seq 1 10); do
          if iwctl station "$dev" show >/dev/null 2>&1; then
            if_ready=1
            break
          fi
          sleep 1
        done
        if [ -z "$if_ready" ]; then
          echo "Wi-Fi adapter '$dev' is not ready (iwd did not claim it) — try again, or blank to skip."
          wifi_prev="$wifi_ssid"; wifi_pass=""
          continue
        fi

        # (b) Scan (may already be in progress) and wait up to ~15s for the SSID.
        iwctl station "$dev" scan >/dev/null 2>&1 || true
        seen=""
        for _ in $(seq 1 15); do
          if iwctl station "$dev" get-networks 2>/dev/null | grep -qF -- "$wifi_ssid"; then
            seen=1
            break
          fi
          sleep 1
        done
        if [ -z "$seen" ]; then
          echo "Network '$wifi_ssid' not found — check the SSID / move closer to the AP."
          wifi_prev="$wifi_ssid"; wifi_pass=""
          continue
        fi

        # (c) Connect non-interactively. iwctl returns once it has ISSUED the
        # connect, so its exit status is not proof of association — poll State
        # for up to ~30s. "connected" as a whole word never matches
        # "disconnected", so this distinguishes success from failure.
        iwctl --passphrase "$wifi_pass" station "$dev" connect "$wifi_ssid" >/dev/null 2>&1 || true
        connected=""
        for _ in $(seq 1 30); do
          if iwctl station "$dev" show 2>/dev/null | grep -qw connected; then
            connected=1
            break
          fi
          sleep 1
        done
        if [ -z "$connected" ]; then
          iwctl station "$dev" disconnect >/dev/null 2>&1 || true
          iwctl known-networks "$wifi_ssid" forget >/dev/null 2>&1 || true
          echo "Could not connect to '$wifi_ssid' — likely a wrong passphrase."
          wifi_prev="$wifi_ssid"; wifi_pass=""
          continue
        fi

        # Success. Capture the known-network profile iwd itself just wrote —
        # its FILENAME and format are authoritative (iwd keeps SSIDs with
        # spaces as plain names; our old hand-rolled rule hex-encoded them, so
        # the installed kiosk never matched the file and never autoconnected).
        # Must happen BEFORE `forget`, which deletes the file. At most one
        # profile exists here: every earlier attempt was forgotten (and stale
        # profiles from a previous boot were removed at the top of this step).
        echo "Wi-Fi OK: connected to '$wifi_ssid'."
        shopt -s nullglob
        for f in /var/lib/iwd/*.psk; do
          wifi_file="$(basename "$f")"
          wifi_profile="$(cat "$f")"
        done
        shopt -u nullglob
        iwctl station "$dev" disconnect >/dev/null 2>&1 || true
        iwctl known-networks "$wifi_ssid" forget >/dev/null 2>&1 || true
        break
      done

      # ---- 4. technician password --------------------------------------------
      echo
      echo "Set a password for the '${adminUser}' account (local console + SSH)."
      while :; do
        read -rsp "Password: " p1; echo
        read -rsp "Confirm:  " p2; echo
        if [ -n "$p1" ] && [ "$p1" = "$p2" ]; then
          break
        fi
        echo "Empty or mismatched — try again."
      done
      # -s: read the password from stdin so it never appears in argv.
      pwhash="$(mkpasswd -m sha-512 -s <<<"$p1")"

      # ---- 5. SSH keys (optional) ---------------------------------------------
      echo
      echo "Optionally add SSH public keys for '${adminUser}'."
      echo "Paste one key per line; empty line to finish (or to skip):"
      keys=()
      while read -rp "> " key; do
        if [ -z "$key" ]; then
          break
        fi
        if ssh-keygen -lf /dev/stdin <<<"$key" >/dev/null 2>&1; then
          keys+=("$key")
        else
          echo "  Not a valid SSH public key — ignored."
        fi
      done

      # ---- 6. target disk (default: largest internal) --------------------------
      # Exclude the device backing the installer medium itself, by name — some
      # USB sticks lie about being removable (RM=0). `findmnt -T` resolves the
      # mount containing the payload dir (a mountpoint on the ISO, a subdir of
      # / on the USB image); readlink -f canonicalizes a by-label symlink
      # source to the real /dev node. The medium is mounted from either a
      # partition (PKNAME = parent disk) or the whole device (PKNAME empty).
      installer_src="$(readlink -f "$(findmnt -no SOURCE -T "${payloadDir}")")"
      installer_disk="$(lsblk -no PKNAME "$installer_src" 2>/dev/null | head -n1)"
      installer_disk="''${installer_disk:-$(basename "$installer_src")}"

      mapfile -t disks < <(
        lsblk -dbno NAME,SIZE,TYPE,RM \
          | awk -v skip="$installer_disk" \
              '$3 == "disk" && $4 == 0 && $1 != skip && $1 !~ /^(zram|ram|loop)/ { print $1, $2 }' \
          | sort -k2 -rn
      )
      if [ "''${#disks[@]}" -eq 0 ]; then
        die_pause "No internal disks found (installer USB /dev/$installer_disk is excluded)."
      fi
      default_disk="/dev/''${disks[0]%% *}"

      echo
      echo "Available disks (installer USB excluded):"
      lsblk -dpno NAME,SIZE,MODEL,TRAN | awk -v d="/dev/$installer_disk" '$1 != d'
      echo
      read -rp "Install to [$default_disk]: " disk
      disk="''${disk:-$default_disk}"
      if [ ! -b "$disk" ]; then
        die_pause "$disk is not a block device."
      fi
      parent="$(lsblk -no PKNAME "$disk" 2>/dev/null | head -n1)"
      if [ "$(basename "$disk")" = "$installer_disk" ] || [ "$parent" = "$installer_disk" ]; then
        die_pause "$disk is the installer USB itself."
      fi

      # ---- 7. summary + single confirmation ------------------------------------
      echo
      echo "About to install:"
      echo "  hostname:  $host"
      echo "  base URL:  $baseurl"
      if [ -n "$wifi_ssid" ]; then
        echo "  wifi:      $wifi_ssid"
      else
        echo "  wifi:      (none — ethernet)"
      fi
      echo "  ssh keys:  ''${#keys[@]}"
      echo "  disk:      $disk  (ALL DATA WILL BE ERASED)"
      echo
      read -rp "Type ERASE to proceed: " confirm
      if [ "$confirm" != "ERASE" ]; then
        die_pause "Not confirmed."
      fi

      # ---- 8. verify + flash ----------------------------------------------------
      echo
      echo ">> Verifying image integrity..."
      ( cd "${payloadDir}" && sha256sum -c mfd-kiosk.raw.zst.sha256 ) \
        || die_pause "Image on this USB is corrupt/truncated. Re-write the installer USB and try again."

      echo ">> Writing image to $disk..."
      zstd -dc "$img" | dd of="$disk" bs=8M conv=fsync status=progress \
        || die_pause "Writing the image failed (disk too small or I/O error)."
      sync
      blockdev --rereadpt "$disk" 2>/dev/null || true
      udevadm settle 2>/dev/null || true

      # ---- 9. stamp per-device identity onto the flashed root ------------------
      # Search the label ONLY on $disk: another attached disk from a previous
      # install could also carry LABEL=nixos.
      rootpart=""
      for _ in $(seq 1 30); do
        rootpart="$(lsblk -pnlo NAME,LABEL "$disk" | awk '$2 == "nixos" { print $1; exit }')"
        if [ -n "$rootpart" ]; then
          break
        fi
        sleep 1
        udevadm settle 2>/dev/null || true
      done
      if [ -z "$rootpart" ]; then
        die_pause "Flashed root partition (LABEL=nixos) not found on $disk."
      fi

      mnt="$(mktemp -d)"
      mount "$rootpart" "$mnt"
      install -d -m 0755 "$mnt${stateDir}" "$mnt${stateDir}/authorized_keys"
      printf '%s\n' "$host" > "$mnt${stateDir}/hostname"
      chmod 0644 "$mnt${stateDir}/hostname"
      printf '%s\n' "$baseurl" > "$mnt${stateDir}/base-url"
      chmod 0644 "$mnt${stateDir}/base-url"
      printf '%s\n' "$pwhash" > "$mnt${stateDir}/${adminUser}.hash"
      chmod 0600 "$mnt${stateDir}/${adminUser}.hash"
      if [ "''${#keys[@]}" -gt 0 ]; then
        printf '%s\n' "''${keys[@]}" > "$mnt${stateDir}/authorized_keys/${adminUser}"
        chmod 0644 "$mnt${stateDir}/authorized_keys/${adminUser}"
      fi

      # Optional Wi-Fi: stamp the exact known-network profile iwd wrote during
      # the live test (captured in step 3) — filename and format are iwd's own,
      # so the installed kiosk is guaranteed to match it. The fallback below
      # should be unreachable (the test must succeed to get here) but keeps a
      # raw hand-off working; it follows iwd's REAL naming rule: alnum, space,
      # '-' and '_' stay plain (<ssid>.psk), anything else is =<lowercase hex>.psk.
      if [ -n "$wifi_ssid" ]; then
        install -d -m 0700 "$mnt/var/lib/iwd"
        if [ -z "$wifi_file" ]; then
          if [[ "$wifi_ssid" =~ ^[A-Za-z0-9\ _-]+$ ]]; then
            wifi_file="$wifi_ssid.psk"
          else
            wifi_hex="$(printf '%s' "$wifi_ssid" | od -An -tx1 | tr -d ' \n')"
            wifi_file="=$wifi_hex.psk"
          fi
          wifi_profile="$(printf '[Security]\nPassphrase=%s' "$wifi_pass")"
        fi
        printf '%s\n' "$wifi_profile" > "$mnt/var/lib/iwd/$wifi_file"
        chmod 0600 "$mnt/var/lib/iwd/$wifi_file"
      fi

      umount "$mnt"
      rmdir "$mnt"
      sync

      # ---- 10. done --------------------------------------------------------------
      echo
      echo "Install complete: '$host' on $disk."
      echo "The root partition grows to fill the disk on first boot. The kiosk"
      echo "screen stays blank until a dashboard token is set — log in as"
      echo "'${adminUser}' (console or SSH) and you will be prompted for it."
      echo
      echo "Remove the USB stick, then press Enter to reboot."
      read -r
      systemctl reboot
    '';
  };
in
{
  options.mfd.flasher = {
    payloadDir = lib.mkOption {
      # A plain string, NEVER a path — a path/store reference interpolated into
      # the wizard script would drag the multi-GB payload into the flasher's
      # runtime closure (squashfs on the ISO, store-bearing root on the USB
      # image), doubling it on the medium.
      type = lib.types.str;
      description = "Absolute runtime directory holding mfd-kiosk.raw.zst + .sha256.";
    };
    payloadPackage = lib.mkOption {
      type = lib.types.package;
      description = "Derivation with mfd-kiosk.raw.zst + .sha256 under stable names, for the medium to embed.";
    };
  };

  config = {
    mfd.flasher.payloadPackage = kioskFlash;

    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    networking.hostName = "mfd-flasher";

    # Bring up the same Wi-Fi stack the installed kiosk uses (iwd) so the wizard
    # can live-test Wi-Fi credentials (scan + associate) before flashing. The
    # radio stays idle until iwctl is driven by the wizard. Redistributable
    # Wi-Fi firmware is carried by both media (the ISO via the installer
    # profile's hardware.enableAllHardware, the USB image via the same option
    # set in flasher-usb.nix).
    networking.wireless.iwd.enable = true;

    # SSH into the live flasher for headless provisioning (run `mfd-install`
    # remotely). Reuses the recovery key(s) baked into the kiosk.
    services.openssh.enable = true;
    users.users.root.openssh.authorizedKeys.keys = kiosk.mfd.kiosk.adminKeys;

    # Passwordless root login on tty2+ as the local escape hatch. The ISO gets
    # the same value from the installer profile (identical definitions merge);
    # the USB image must set it itself.
    users.users.root.initialHashedPassword = "";

    # The wizard owns tty1. On the ISO the installer profile autologs in a
    # `nixos` user there (set WITHOUT mkDefault, hence mkForce); on the USB
    # image the mkForce is a harmless no-op. A getty stays on tty2+ either way.
    services.getty.autologinUser = lib.mkForce null;
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@tty1".enable = false;

    systemd.services.mfd-installer = {
      description = "MFD kiosk install wizard";
      wantedBy = [ "multi-user.target" ];
      conflicts = [ "getty@tty1.service" ];
      # Never rate-limit restarts: die_pause blocks on Enter, so a restart loop
      # is always user-paced, and the wizard must survive any number of aborts.
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        # idle = wait until boot jobs stop printing to the console (getty trick),
        # without an After=multi-user.target ordering cycle.
        Type = "idle";
        ExecStart = "${mfdInstall}/bin/mfd-install";
        StandardInput = "tty-force";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
        Restart = "always";
        RestartSec = "2";
      };
    };

    # Also runnable by hand (tty2 shell or SSH as root) for headless provisioning.
    environment.systemPackages = [ mfdInstall ];
  };
}
