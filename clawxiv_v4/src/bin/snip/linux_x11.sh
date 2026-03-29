#!/usr/bin/env bash
# bin/snip/linux_x11.sh — Linux/X11 selected-text capture stub
#
# STUB: text retrieval is implemented; provenance detection is not.
#
# Text retrieval:
#   xclip or xsel can read the PRIMARY selection (what is currently
#   highlighted) or the CLIPBOARD (what was Ctrl-C'd).
#   PRIMARY is usually preferable for "what the user has selected right now".
#
# Provenance detection on Linux/X11 requires identifying the focused window
# and its associated URL if it is a browser.  This can be done via:
#   - xdotool getactivewindow getwindowname  (window title, not URL)
#   - wmctrl -lx  (window list with class names)
#   - For browsers: use a browser extension that writes the current URL
#     to a known file or environment variable, or use xdotool to send
#     Ctrl-L followed by Ctrl-C on the address bar (fragile).
#
# Until provenance detection is implemented, this stub attributes all
# snips to the senior author and records an empty URL.
# Set CLAWXIV_SNIP_AUTHOR and CLAWXIV_SNIP_URL to override manually.

set -euo pipefail

SNIP_TMP_PREFIX="${SNIP_TMP_PREFIX:-/tmp/clawxiv_snip_$$}"
SENIOR_AUTHOR="${CLAWXIV_SENIOR_AUTHOR:-András Kornai}"
AUTHOR="${CLAWXIV_SNIP_AUTHOR:-$SENIOR_AUTHOR}"
SOURCE_URL="${CLAWXIV_SNIP_URL:-}"

# ── Retrieve text ─────────────────────────────────────────────────────────────
TOOL="${CLAWXIV_X11_PASTE_TOOL:-auto}"
if [ "$TOOL" = "auto" ]; then
    if command -v xclip  &>/dev/null; then TOOL=xclip
    elif command -v xsel &>/dev/null; then TOOL=xsel
    else TOOL=none; fi
fi

case "$TOOL" in
    xclip)
        TEXT="$(xclip -selection primary -o 2>/dev/null \
                || xclip -selection clipboard -o 2>/dev/null)" ;;
    xsel)
        TEXT="$(xsel --primary --output 2>/dev/null \
                || xsel --clipboard --output 2>/dev/null)" ;;
    none)
        echo "snip/linux_x11: no paste tool found. Install xclip or xsel." >&2
        exit 3 ;;
esac

if [[ -z "${TEXT// }" ]]; then
    echo "snip/linux_x11: selection/clipboard is empty." >&2
    exit 1
fi

# ── TODO: provenance detection ────────────────────────────────────────────────
# Implement window-class inspection here.
# Example skeleton (requires xdotool):
#
# WIN_CLASS=$(xdotool getactivewindow getwindowclassname 2>/dev/null || echo "")
# case "$WIN_CLASS" in
#     *firefox*|*chrome*|*chromium*)
#         # browser detected; attempt URL retrieval
#         ;;
#     *emacs*|*vim*|*code*)
#         AUTHOR="$SENIOR_AUTHOR"
#         ;;
# esac

echo "snip/linux_x11: provenance detection not yet implemented." >&2
echo "  Attributed to: ${AUTHOR}" >&2
echo "  Override with CLAWXIV_SNIP_AUTHOR and CLAWXIV_SNIP_URL." >&2

# ── Write output ──────────────────────────────────────────────────────────────
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s' "$TEXT" > "${SNIP_TMP_PREFIX}.txt"
python3 -c "
import json, sys
d = {'author': sys.argv[1], 'url': sys.argv[2], 'ts': sys.argv[3],
     'app': 'unknown', 'bundle': 'unknown'}
print(json.dumps(d))
" "$AUTHOR" "$SOURCE_URL" "$TS" > "${SNIP_TMP_PREFIX}.meta"
