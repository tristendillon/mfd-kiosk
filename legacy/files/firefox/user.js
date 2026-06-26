// MFD kiosk Firefox profile preferences.
// This file is copied into the ephemeral runtime profile on each session.
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
// Only one trusted first-party dashboard is ever shown, so per-site isolation
// (Fission) and the extra content processes are pure overhead. This trades
// some sandbox isolation for a markedly smaller footprint.
user_pref("fission.autostart", false);
user_pref("dom.ipc.processCount", 1);
user_pref("dom.ipc.processCount.webIsolated", 1);
user_pref("browser.tabs.remote.autostart", true);

// No media playback on the dashboard: drop the audio/video decoder process.
user_pref("media.rdd-process.enabled", false);
user_pref("media.gmp-provider.enabled", false);

// No add-ons in the ephemeral profile: run built-in extensions in-process
// instead of spawning a dedicated WebExtensions process.
user_pref("extensions.webextensions.remote", false);

// Fold networking into the parent process (one fewer helper).
user_pref("network.process.enabled", false);

// Machinery the kiosk never displays.
user_pref("browser.newtabpage.enabled", false);
user_pref("extensions.pocket.enabled", false);
