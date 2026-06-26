#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Firefox lockdown.
#
#   - policies.json: system-wide enterprise policy (read from /etc/firefox).
#     Disables updates, telemetry, studies, accounts, onboarding, etc.
#   - user.js: staged canonical copy. The kiosk session copies this into a
#     throwaway profile under $XDG_RUNTIME_DIR on every launch
#     (see files/openbox/autostart), so nothing persists on disk.
# ---------------------------------------------------------------------------

install -d -m 755 /etc/firefox/policies
install -m 644 ./files/firefox/policies.json /etc/firefox/policies/policies.json

install -d -m 755 /etc/mfd-kiosk/firefox
install -m 644 ./files/firefox/user.js /etc/mfd-kiosk/firefox/user.js
