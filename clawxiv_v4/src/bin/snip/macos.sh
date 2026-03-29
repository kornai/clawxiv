#!/usr/bin/env bash
# bin/snip/macos.sh — macOS selected-text capture with provenance detection
#
# Strategy:
#   1. Simulate Cmd-C to copy the current selection to clipboard.
#      (If the user has already copied, this is a no-op; the clipboard
#       already holds what they want.)
#   2. Read the clipboard text via pbpaste.
#   3. Use AppleScript to identify the frontmost application and, for
#      browsers, the current page URL.
#   4. Map (app, URL) to a provenance record: author name + source URL.
#   5. Write ${SNIP_TMP_PREFIX}.txt and ${SNIP_TMP_PREFIX}.meta.
#
# Provenance mapping (extend AUTHOR_MAP below to add more services):
#   claude.ai             → Claude Sonnet 4.6 (Anthropic)
#   chat.openai.com       → GPT (OpenAI)
#   gemini.google.com     → Gemini (Google)
#   any editor app        → value of $CLAWXIV_SENIOR_AUTHOR
#   unknown browser page  → Unknown (URL recorded for manual resolution)
#
# The Cmd-C simulation is done only when CLAWXIV_SNIP_COPY_FIRST=1 (default).
# Set to 0 if the text is already on the clipboard.

set -euo pipefail

SNIP_TMP_PREFIX="${SNIP_TMP_PREFIX:-/tmp/clawxiv_snip_$$}"
SENIOR_AUTHOR="${CLAWXIV_SENIOR_AUTHOR:-András Kornai}"
COPY_FIRST="${CLAWXIV_SNIP_COPY_FIRST:-1}"

# ── Known editor bundle IDs ───────────────────────────────────────────────────
# These apps produce text written by the senior author.
EDITOR_BUNDLES=(
    "org.gnu.Emacs"
    "com.apple.TextEdit"
    "com.sublimetext.4"
    "com.microsoft.VSCode"
    "com.jetbrains.intellij"
    "org.vim.MacVim"
    "com.hogbaysoftware.TaskPaper"
    "com.coteditor.CotEditor"
    "com.barebones.bbedit"
    "com.apple.Notes"
    "com.apple.mail"           # Mail.app — composing = senior author
)

# ── Known browser bundle IDs ─────────────────────────────────────────────────
BROWSER_BUNDLES=(
    "com.apple.Safari"
    "com.google.Chrome"
    "org.mozilla.firefox"
    "com.operasoftware.Opera"
    "company.thebrowser.Browser"  # Arc
    "com.microsoft.edgemac"
)

# ── URL → author mapping ──────────────────────────────────────────────────────
# Patterns matched against the page URL (case-insensitive substring).
# First match wins.  Extend as needed.
declare -A URL_AUTHOR_MAP
URL_AUTHOR_MAP=(
    ["claude.ai"]="Claude Sonnet 4.6 (Anthropic)"
    ["chat.openai.com"]="GPT (OpenAI)"
    ["chatgpt.com"]="GPT (OpenAI)"
    ["gemini.google.com"]="Gemini (Google)"
    ["bard.google.com"]="Gemini (Google)"
    ["copilot.microsoft.com"]="Copilot (Microsoft)"
    ["perplexity.ai"]="Perplexity AI"
)

# ── Step 1: optionally simulate Cmd-C ────────────────────────────────────────
if [[ "$COPY_FIRST" == "1" ]]; then
    osascript -e '
        tell application "System Events"
            keystroke "c" using {command down}
        end tell
    ' 2>/dev/null || true
    # Brief pause for clipboard to settle
    sleep 0.15
fi

# ── Step 2: read clipboard ────────────────────────────────────────────────────
TEXT="$(pbpaste)"
if [[ -z "${TEXT// }" ]]; then
    echo "snip/macos: clipboard is empty." >&2
    exit 1
fi

# ── Step 3: identify frontmost app and URL ────────────────────────────────────
APP_INFO="$(osascript << 'ASEOF'
set result to ""
try
    tell application "System Events"
        set frontApp to first application process whose frontmost is true
        set appName to name of frontApp
        set bundleID to bundle identifier of frontApp
        set result to appName & "|" & bundleID & "|"
    end tell
    -- Try to get URL from common browsers
    try
        tell application "Safari"
            if (count of windows) > 0 then
                set result to result & (URL of current tab of front window)
            end if
        end tell
    end try
    try
        tell application "Google Chrome"
            if (count of windows) > 0 then
                set result to result & (URL of active tab of front window)
            end if
        end tell
    end try
    try
        tell application "Firefox"
            -- Firefox requires extra permissions; may be empty
        end tell
    end try
    try
        tell application "Opera"
            if (count of windows) > 0 then
                set result to result & (URL of front document)
            end if
        end tell
    end try
on error
end try
return result
ASEOF
)"

# Parse: "AppName|bundleID|URL"
APP_NAME="$(echo "$APP_INFO" | cut -d'|' -f1)"
BUNDLE_ID="$(echo "$APP_INFO" | cut -d'|' -f2)"
PAGE_URL="$(echo "$APP_INFO"  | cut -d'|' -f3-)"   # everything after second |

# ── Step 4: determine provenance ──────────────────────────────────────────────
AUTHOR=""
SOURCE_URL="$PAGE_URL"

# Check if it's an editor (senior author)
IS_EDITOR=false
for b in "${EDITOR_BUNDLES[@]}"; do
    if [[ "$BUNDLE_ID" == "$b" ]]; then
        IS_EDITOR=true; break
    fi
done

if $IS_EDITOR; then
    AUTHOR="$SENIOR_AUTHOR"
    SOURCE_URL=""   # editor text has no URL provenance
else
    # Check if it's a browser; map URL to author
    IS_BROWSER=false
    for b in "${BROWSER_BUNDLES[@]}"; do
        if [[ "$BUNDLE_ID" == "$b" ]]; then
            IS_BROWSER=true; break
        fi
    done

    if $IS_BROWSER && [[ -n "$PAGE_URL" ]]; then
        for pattern in "${!URL_AUTHOR_MAP[@]}"; do
            if [[ "$PAGE_URL" == *"$pattern"* ]]; then
                AUTHOR="${URL_AUTHOR_MAP[$pattern]}"
                break
            fi
        done
        # If no pattern matched, source URL is preserved for manual resolution
        [[ -z "$AUTHOR" ]] && AUTHOR="Unknown (from ${APP_NAME})"
    else
        # Unknown app — fall back to senior author with a warning
        AUTHOR="$SENIOR_AUTHOR"
        SOURCE_URL=""
        echo "snip/macos: unrecognised app '${APP_NAME}' (${BUNDLE_ID}); attributed to senior author." >&2
        echo "  Override with CLAWXIV_SNIP_AUTHOR if incorrect." >&2
    fi
fi

# Allow manual override
[[ -n "${CLAWXIV_SNIP_AUTHOR:-}" ]] && AUTHOR="$CLAWXIV_SNIP_AUTHOR"
[[ -n "${CLAWXIV_SNIP_URL:-}"    ]] && SOURCE_URL="$CLAWXIV_SNIP_URL"

# ── Step 5: write output files ────────────────────────────────────────────────
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

printf '%s' "$TEXT" > "${SNIP_TMP_PREFIX}.txt"

python3 -c "
import json, sys
d = {'author': sys.argv[1], 'url': sys.argv[2], 'ts': sys.argv[3],
     'app': sys.argv[4], 'bundle': sys.argv[5]}
print(json.dumps(d, ensure_ascii=False))
" "$AUTHOR" "$SOURCE_URL" "$TS" "${APP_NAME:-unknown}" "${BUNDLE_ID:-unknown}" \
  > "${SNIP_TMP_PREFIX}.meta"

echo "snip/macos: captured ${#TEXT} chars from '${APP_NAME}' → author: ${AUTHOR}" >&2
