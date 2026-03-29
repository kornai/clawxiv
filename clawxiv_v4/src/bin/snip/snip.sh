#!/usr/bin/env sh
# bin/snip/snip.sh — platform-dispatching selected-text capture with provenance
#
# Retrieves the current selection (or clipboard) and attempts to identify
# the provenance of the text: who wrote it and from what source URL.
#
# Output (to stdout, one line each):
#   LINE 1: the captured text (may be multi-line; terminated by a sentinel)
#   LINE 2: detected author name
#   LINE 3: source URL (empty string if not determinable)
#   LINE 4: ISO 8601 timestamp
#
# Because multi-line text makes line-based parsing fragile, the output is
# instead written to three files named by $SNIP_TMP_PREFIX:
#   ${SNIP_TMP_PREFIX}.txt   — raw captured text
#   ${SNIP_TMP_PREFIX}.meta  — JSON: {"author":..., "url":..., "ts":...}
#
# The calling script (bin/clawxiv-snip) reads these files.
#
# Exit codes:
#   0   text captured successfully
#   1   clipboard/selection empty or user cancelled
#   2   platform not supported
#   3   required tool missing

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SNIP_TMP_PREFIX="${SNIP_TMP_PREFIX:-/tmp/clawxiv_snip_$$}"

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo macos ;;
        Linux)
            if [ -n "${WAYLAND_DISPLAY:-}" ]; then echo linux_wayland
            else echo linux_x11; fi ;;
        MINGW*|MSYS*|CYGWIN*) echo windows ;;
        *) echo unknown ;;
    esac
}

PLATFORM="${CLAWXIV_PLATFORM:-$(detect_platform)}"

export SNIP_TMP_PREFIX

case "$PLATFORM" in
    macos)        exec "$SCRIPT_DIR/macos.sh"         "$@" ;;
    linux_x11)    exec "$SCRIPT_DIR/linux_x11.sh"    "$@" ;;
    linux_wayland) exec "$SCRIPT_DIR/linux_wayland.sh" "$@" ;;
    windows)      exec "$SCRIPT_DIR/windows.ps1"     "$@" ;;
    *)
        echo "snip: unsupported platform '$PLATFORM'" >&2
        exit 2 ;;
esac
