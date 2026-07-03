{ config, pkgs, lib, ... }:

# Boots straight into fullscreen firefox-esr (Gecko) under the cage Wayland
# compositor. Replaces the previous cog/WPE-WebKit launcher; cage, the cage-tty1
# hardening, hardware.graphics and the sleep-disable stay as-is. Dropping cog
# also drops the whole webkitgtk subtree from the closure — it was only ever a
# transitive dependency of cog and is named nowhere else.
let
  cfg = config.mfd.kiosk;

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

    // --- VM / vmwgfx GPU fallbacks (RESERVE — uncomment only if the dashboard
    // renders blank/garbled in VMware; the Gecko analog of the old cog
    // WEBKIT_DISABLE_DMABUF_RENDERER workaround). ---
    // user_pref("gfx.webrender.software", true);
    // user_pref("widget.dmabuf.force-enabled", false);
    // user_pref("media.ffmpeg.vaapi.enabled", false);
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

  # No token -> no browser -> blank tty1. Must be a LIST: the cage module sets
  # its own ConditionPathExists as a string ("/dev/tty1"), and the unit-option
  # merge only concatenates when at least one definition is a list.
  systemd.services."cage-tty1".unitConfig.ConditionPathExists = [ cfg.tokenFile ];

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

  # Crash -> restart (replaces the old 2-minute healthcheck poll). cage names the
  # unit after the tty, so it stays `cage-tty1` regardless of which program it
  # runs. NOTE: confirm on first boot with `systemctl status cage-tty1`.
  systemd.services."cage-tty1".serviceConfig = {
    Restart = lib.mkForce "always";
    RestartSec = "2s";
    # Soft cap on 2 GB boards: past this the kernel reclaims this slice's pages
    # (into zram) rather than killing it. Firefox is heavier than cog was, so
    # treat this as a starting value and re-check real RSS after first boot; a
    # hard OOM is left to earlyoom (slim.nix), which trips before the box stalls.
    MemoryHigh = "1400M";
  };

  # GPU / WebGL for Google Maps — mesa covers Intel i915 and AMD amdgpu, so one
  # image accelerates on both board families.
  hardware.graphics.enable = true;

  # Display-only appliance: never sleep, and (by running no idle daemon) never
  # blank. This replaces the X DPMS config in the old power.sh.
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
}
