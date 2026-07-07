{ config, pkgs, lib, ... }:

# Boots straight into fullscreen firefox-esr (Gecko) under the cage Wayland
# compositor. Bundles the cage-tty1 hardening (blank tty1 until a token exists,
# crash-restart), enables hardware.graphics for WebGL, and disables all sleep so
# the display stays live as an always-on appliance.
let
  cfg = config.mfd.kiosk;

  # Persistent (survives reboots — the ext4 root is not tmpfs) store for the one
  # bit of Firefox profile state we DO want to keep: per-site zoom. Everything
  # else in the profile stays throwaway. Owned by the kiosk user so Firefox can
  # write to it; see the symlink in the launcher and the tmpfiles rule below.
  zoomStateDir = "/var/lib/mfd-kiosk/firefox";

  # Enterprise policy baked INTO the package via the firefox wrapper
  # (lib/firefox/distribution/policies.json). Self-contained, store-path pinned,
  # no /etc file and no programs.firefox module. Only the lightweight wrapper
  # rebuilds — firefox-esr-unwrapped is fetched from cache (no source build).
  kioskFirefox = pkgs.firefox-esr.override {
    extraPolicies = {
      DisableAppUpdate = true;
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisableFirefoxAccounts = true;
      DisableProfileRefresh = true;
      DisablePocket = true;
      DontCheckDefaultBrowser = true;
      NoDefaultBookmarks = true;
      OfferToSaveLogins = false;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      PasswordManagerEnabled = false;
      SearchSuggestEnabled = false;
      UserMessaging = {
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        MoreFromMozilla = false;
        SkipOnboarding = true;
        UrlbarInterventions = false;
        WhatsNew = false;
      };
    };
  };

  # Per-session prefs, kept in the store and installed into the throwaway profile
  # on every launch. Mirrors the legacy /etc/mfd-kiosk/firefox/user.js, but is
  # fully self-contained in this module.
  userJs = pkgs.writeText "mfd-firefox-user.js" ''
    // MFD kiosk Firefox profile preferences (copied into the ephemeral profile each launch).
    user_pref("browser.shell.checkDefaultBrowser", false);
    user_pref("browser.defaultbrowser.notificationbar", false);

    user_pref("browser.startup.homepage_override.mstone", "ignore");
    user_pref("browser.startup.couldRestoreSession.count", 0);
    user_pref("startup.homepage_welcome_url", "");
    user_pref("startup.homepage_welcome_url.additional", "");
    user_pref("trailhead.firstrun.didSeeAboutWelcome", true);

    user_pref("browser.cache.disk.enable", false);
    user_pref("browser.cache.disk.capacity", 0);
    user_pref("browser.cache.disk.smart_size.enabled", false);
    user_pref("browser.cache.offline.enable", false);
    user_pref("browser.cache.memory.enable", true);

    user_pref("places.history.enabled", false);
    user_pref("browser.formfill.enable", false);
    user_pref("signon.rememberSignons", false);

    user_pref("browser.sessionstore.resume_from_crash", false);
    user_pref("browser.sessionstore.max_tabs_undo", 0);
    user_pref("browser.sessionstore.max_windows_undo", 0);
    user_pref("browser.sessionstore.interval", 600000);

    user_pref("datareporting.healthreport.uploadEnabled", false);
    user_pref("datareporting.policy.dataSubmissionEnabled", false);
    user_pref("toolkit.telemetry.enabled", false);
    user_pref("toolkit.telemetry.unified", false);
    user_pref("app.shield.optoutstudies.enabled", false);
    user_pref("extensions.getAddons.showPane", false);
    user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
    user_pref("browser.discovery.enabled", false);

    user_pref("identity.fxaccounts.enabled", false);
    user_pref("services.sync.engine.addons", false);
    user_pref("services.sync.engine.bookmarks", false);
    user_pref("services.sync.engine.history", false);
    user_pref("services.sync.engine.passwords", false);
    user_pref("services.sync.engine.prefs", false);
    user_pref("services.sync.engine.tabs", false);

    user_pref("browser.search.suggest.enabled", false);
    user_pref("browser.urlbar.suggest.searches", false);
    user_pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
    user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);

    user_pref("ui.prefersReducedMotion", 1);
    user_pref("gfx.webrender.all", true);

    // --- Single-tab kiosk: collapse Firefox's multi-process model to cut RAM. ---
    user_pref("fission.autostart", false);
    user_pref("dom.ipc.processCount", 1);
    user_pref("dom.ipc.processCount.webIsolated", 1);
    user_pref("browser.tabs.remote.autostart", true);
    user_pref("media.rdd-process.enabled", false);
    user_pref("media.gmp-provider.enabled", false);
    user_pref("extensions.webextensions.remote", false);
    user_pref("network.process.enabled", false);
    user_pref("browser.newtabpage.enabled", false);
    user_pref("extensions.pocket.enabled", false);

    // --- Bounded caches & no back/forward page cache: single-URL kiosk. ---
    user_pref("browser.cache.memory.capacity", 51200);
    user_pref("browser.sessionhistory.max_total_viewers", 0);
    user_pref("browser.sessionhistory.max_entries", 5);
    user_pref("toolkit.cosmeticAnimations.enabled", false);
    user_pref("browser.tabs.animate", false);
    user_pref("browser.fullscreen.animate", false);

    // --- Kiosk: hide the mouse cursor. Enables chrome/userContent.css (a
    // user-origin sheet whose `cursor: none !important` beats page-set
    // `cursor: pointer`); the sheet is installed by the launcher below. ---
    user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

    // --- VM / vmwgfx GPU fallbacks (RESERVE — uncomment only if the dashboard
    // renders blank/garbled in VMware; these force Firefox onto safer,
    // software/no-dmabuf rendering paths for the vmwgfx driver). ---
    // user_pref("gfx.webrender.software", true);
    // user_pref("widget.dmabuf.force-enabled", false);
    // user_pref("media.ffmpeg.vaapi.enabled", false);
  '';

  # Global "no cursor" sheet for ALL web content. Installed into the ephemeral
  # profile's chrome/ dir each launch, mirroring how user.js is installed.
  # userContent.css is user-origin, so `!important` here beats any author-set
  # cursor:pointer on links/buttons and the text I-beam over inputs.
  userContentCss = pkgs.writeText "mfd-firefox-userContent.css" ''
    *, *::before, *::after { cursor: none !important; }
  '';

  # Fully-transparent XCursor theme. wlroots/cage draws a default cursor at
  # startup (before Firefox paints) and during the crash-restart gap — cases
  # userContent.css can't reach. Point cage at this so its own cursor is
  # invisible too. Build-time deps only; only the tiny cursor files ship.
  transparentCursor = pkgs.runCommand "mfd-transparent-cursor" {
    nativeBuildInputs = [ pkgs.xcursorgen pkgs.imagemagick ];
  } ''
    mkdir -p "$out/share/icons/mfd-blank/cursors"
    magick -size 32x32 xc:transparent blank.png   # >= nominal size or xcursorgen errors
    printf '32 0 0 blank.png\n' > blank.conf       # <size> <xhot> <yhot> <file>
    xcursorgen blank.conf "$out/share/icons/mfd-blank/cursors/left_ptr"
    cd "$out/share/icons/mfd-blank/cursors"
    for n in default arrow top_left_arrow pointer hand hand1 hand2 \
             xterm text ibeam crosshair watch wait progress \
             grab grabbing move all-scroll not-allowed help question_arrow \
             context-menu n-resize s-resize e-resize w-resize \
             ne-resize nw-resize se-resize sw-resize ns-resize ew-resize \
             nesw-resize nwse-resize col-resize row-resize; do
      [ -e "$n" ] || ln -s left_ptr "$n"
    done
    printf '[Icon Theme]\nName=mfd-blank\nComment=Transparent kiosk cursor\n' \
      > "$out/share/icons/mfd-blank/index.theme"
  '';

  # firefox's URL carries the per-device token, which is NOT known at build time,
  # so we read it from the runtime token file and exec firefox from a wrapper.
  launcher = pkgs.writeShellScript "mfd-kiosk-launch" ''
    set -eu

    if [ ! -r "${cfg.tokenFile}" ]; then
      echo "mfd-kiosk: ${cfg.tokenFile} missing/unreadable; run 'sudo mfd-set-token'" >&2
      sleep 30   # avoid a tight crash-loop while unprovisioned
      exit 1
    fi

    # shellcheck disable=SC1090
    . "${cfg.tokenFile}"

    if [ -z "''${KIOSK_URL:-}" ]; then
      echo "mfd-kiosk: KIOSK_URL not set in ${cfg.tokenFile}" >&2
      sleep 30
      exit 1
    fi

    # cage is pure Wayland (no Xwayland); Firefox must be told to use Wayland or
    # it will try X11 and fail to start.
    export MOZ_ENABLE_WAYLAND=1

    # Throwaway profile under the runtime dir: nothing persists across reboots.
    PROFILE="''${XDG_RUNTIME_DIR}/mfd-firefox-profile"
    rm -rf "$PROFILE"
    mkdir -p "$PROFILE"
    install -m 644 ${userJs} "$PROFILE/user.js"
    install -D -m 644 ${userContentCss} "$PROFILE/chrome/userContent.css"

    # --- Persist per-site zoom across reboots. The profile is a throwaway (wiped
    # just above), but some TVs/kiosks scale badly and render the dashboard tiny;
    # a technician zooms in once (Ctrl-+) and expects it to stick. Firefox stores
    # full-page zoom per host in content-prefs.sqlite, so we symlink JUST that
    # one file to a persistent, kiosk-owned dir — nothing else in the profile
    # persists. SQLite resolves the symlink, so its -wal/-shm land in the
    # persistent dir too and a zoom survives even a hard power-cut. Zoom is keyed
    # by host (browser.zoom.siteSpecific, on by default), so it applies no matter
    # which per-device token is appended to the URL path.
    ln -sf "${zoomStateDir}/content-prefs.sqlite" "$PROFILE/content-prefs.sqlite"

    exec ${kioskFirefox}/bin/firefox-esr ${lib.escapeShellArgs cfg.extraFirefoxArgs} \
      --profile "$PROFILE" --kiosk "$KIOSK_URL"
  '';
in
{
  # cage = single-app Wayland kiosk compositor; auto-logs in the kiosk user and
  # renders firefox-esr fullscreen on the primary display.
  services.cage = {
    enable = true;
    user = cfg.kioskUser;
    program = launcher;
  };

  # Persistent, kiosk-owned home for content-prefs.sqlite (per-site zoom). Must
  # exist and be writable by the kiosk user before cage launches Firefox; the
  # launcher symlinks the throwaway profile's content-prefs.sqlite in here.
  # 0700: only the kiosk user needs it. tmpfiles creates the parent as needed.
  systemd.tmpfiles.rules = [
    "d ${zoomStateDir} 0700 ${cfg.kioskUser} ${cfg.kioskUser} -"
  ];

  # cage/wlroots draws its OWN default cursor (at startup before Firefox paints,
  # and during the crash-restart gap) — the launcher's env can't reach it since
  # the launcher IS cage's `program` (its exports land in Firefox, not cage).
  # Point cage at a fully-transparent XCursor theme so that cursor is invisible
  # too. XCURSOR_PATH is the dir CONTAINING the theme dir.
  services.cage.environment = {
    XCURSOR_THEME = "mfd-blank";
    XCURSOR_PATH  = "${transparentCursor}/share/icons";
    XCURSOR_SIZE  = "32";
    # vmwgfx escape hatch: if the VMware HW cursor plane ignores the transparent
    # theme, uncomment to force wlroots onto software cursors (which honor it).
    # WLR_NO_HARDWARE_CURSORS = "1";
  };

  # No token -> no browser -> blank tty1. Must be a LIST: the cage module sets
  # its own ConditionPathExists as a string ("/dev/tty1"), and the unit-option
  # merge only concatenates when at least one definition is a list.
  systemd.services."cage-tty1".unitConfig.ConditionPathExists = [ cfg.tokenFile ];

  # Never stop restarting. systemd's default start-rate limit (5 starts / 10s),
  # combined with RestartSec=2s below, would trip during a crash-loop and drop
  # cage into a failed state — a permanently blank screen until the daily reboot.
  # A kiosk must keep retrying forever; RestartSec still throttles to every 2s.
  systemd.services."cage-tty1".unitConfig.StartLimitIntervalSec = 0;

  # Start the browser the moment a token is written (mfd-set-token also does an
  # explicit restart to pick up token *changes*; this covers first creation).
  systemd.paths.mfd-kiosk-start = {
    description = "Start kiosk browser when the dashboard token appears";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathExists = cfg.tokenFile;
      Unit = "cage-tty1.service";
    };
  };

  # Keep tty1 truly blank while cage is condition-blocked (no token yet):
  # otherwise logind's autovt would put a login prompt there. Local debug login
  # stays available on tty2+.
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Don't race the network: on a fast reboot cage would otherwise launch firefox
  # before DHCP finishes, loading the dashboard URL while offline (blank/error
  # page with no auto-retry). Order after network-online.target so the browser
  # opens only once a link is up. `wants` (not `requires`) means a genuinely
  # offline box still launches after wait-online's 30s timeout rather than
  # staying blank forever.
  systemd.services."cage-tty1".after = [ "network-online.target" ];
  systemd.services."cage-tty1".wants = [ "network-online.target" ];

  # Crash -> restart. cage names the unit after the tty, so it stays `cage-tty1`
  # regardless of which program it runs. NOTE: confirm on first boot with
  # `systemctl status cage-tty1`.
  systemd.services."cage-tty1".serviceConfig = {
    Restart = lib.mkForce "always";
    RestartSec = "2s";
    # Soft cap on 2 GB boards: past this the kernel reclaims this slice's pages
    # (into zram) rather than killing it. Treat this as a starting value and
    # re-check real RSS after first boot; a hard OOM is left to earlyoom
    # (slim.nix), which trips before the box stalls.
    MemoryHigh = "1400M";
  };

  # GPU / WebGL for Google Maps — mesa covers Intel i915 and AMD amdgpu, so one
  # image accelerates on both board families.
  hardware.graphics.enable = true;

  # Display-only appliance: never sleep, and (by running no idle daemon) never
  # blank.
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
}
