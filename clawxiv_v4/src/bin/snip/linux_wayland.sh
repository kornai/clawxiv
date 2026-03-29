#!/usr/bin/env bash
# bin/snip/linux_wayland.sh — Linux/Wayland selected-text capture stub
#
# STUB: text retrieval is implemented; provenance detection is not.
#
# Text retrieval on Wayland uses wl-paste (from wl-clipboard).
# PRIMARY selection (highlighted text without Ctrl-C) is available
# via:  wl-paste --primary
# CLIPBOARD is via: wl-paste
#
# Provenance detection on Wayland is harder than on X11 because
# there is no universal mechanism for querying the focused window's
# metadata from outside.  Compositor-specific protocols exist:
#   - sway/i3: swaymsg -t get_tree | jq to find focused window
#   - GNOME Shell: gdbus call on org.gnome.Shell
#   - KWin: qdbus org.kde.KWin
# A browser extension writing the current URL to a temp file or
# socket is the most portable approach for URL detection.

set -euo pipefail

SNIP_TMP_PREFIX="${SNIP_TMP_PREFIX:-/tmp/clawxiv_snip_$$}"
SENIOR_AUTHOR="${CLAWXIV_SENIOR_AUTHOR:-András Kornai}"
AUTHOR="${CLAWXIV_SNIP_AUTHOR:-$SENIOR_AUTHOR}"
SOURCE_URL="${CLAWXIV_SNIP_URL:-}"

# ── Retrieve text ─────────────────────────────────────────────────────────────
if ! command -v wl-paste &>/dev/null; then
    echo "snip/linux_wayland: wl-paste not found. Install wl-clipboard." >&2
    exit 3
fi

TEXT="$(wl-paste --primary 2>/dev/null || wl-paste 2>/dev/null || true)"
if [[ -z "${TEXT// }" ]]; then
    echo "snip/linux_wayland: selection/clipboard is empty." >&2
    exit 1
fi

# ── TODO: provenance detection ────────────────────────────────────────────────
# Implement compositor-specific window inspection here.
# Sway example skeleton:
#
# if command -v swaymsg &>/dev/null; then
#     APP_ID=$(swaymsg -t get_tree | python3 -c "
# import json,sys
# def find_focused(n):
#     if n.get('focused'): return n.get('app_id','')
#     for c in n.get('nodes',[])+n.get('floating_nodes',[]): r=find_focused(c)
#     if r: return r
#     return ''
# print(find_focused(json.load(sys.stdin)))
# ")
#     case "$APP_ID" in
#         *firefox*|*chromium*) # browser ;;
#         *emacs*|*vim*)        AUTHOR="$SENIOR_AUTHOR" ;;
#     esac
# fi

echo "snip/linux_wayland: provenance detection not yet implemented." >&2
echo "  Attributed to: ${AUTHOR}" >&2

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s' "$TEXT" > "${SNIP_TMP_PREFIX}.txt"
python3 -c "
import json, sys
d = {'author': sys.argv[1], 'url': sys.argv[2], 'ts': sys.argv[3],
     'app': 'unknown', 'bundle': 'unknown'}
print(json.dumps(d))
" "$AUTHOR" "$SOURCE_URL" "$TS" > "${SNIP_TMP_PREFIX}.meta"
