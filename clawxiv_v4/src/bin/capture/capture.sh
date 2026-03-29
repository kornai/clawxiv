#!/usr/bin/env sh
# capture.sh — platform-dispatching screen-region capture
#
# Detects the host platform and delegates to the appropriate implementation.
# Output: writes a PNG to stdout, or to $CAPTURE_OUT if set.
#
# Environment variables honoured:
#   CAPTURE_OUT     destination path (default: /tmp/clawxiv_capture_$$.png)
#   CAPTURE_TITLE   window title hint for implementations that support it
#
# Exit codes:
#   0   capture successful, file written to $CAPTURE_OUT
#   1   user cancelled or no region selected
#   2   platform not supported
#   3   required tool missing on this platform

set -e

CAPTURE_OUT="${CAPTURE_OUT:-/tmp/clawxiv_capture_$$.png}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo macos ;;
        Linux)
            # Distinguish Wayland from X11
            if [ -n "${WAYLAND_DISPLAY:-}" ]; then echo linux_wayland
            else echo linux_x11
            fi ;;
        MINGW*|MSYS*|CYGWIN*) echo windows ;;
        *) echo unknown ;;
    esac
}

PLATFORM="${CLAWXIV_PLATFORM:-$(detect_platform)}"

case "$PLATFORM" in
    macos)        exec "$SCRIPT_DIR/macos.sh"        "$@" ;;
    linux_x11)    exec "$SCRIPT_DIR/linux_x11.sh"   "$@" ;;
    linux_wayland) exec "$SCRIPT_DIR/linux_wayland.sh" "$@" ;;
    windows)      exec "$SCRIPT_DIR/windows.ps1"    "$@" ;;
    *)
        echo "capture: unsupported platform '$PLATFORM'" >&2
        echo "Set CLAWXIV_PLATFORM to one of: macos linux_x11 linux_wayland windows" >&2
        exit 2 ;;
esac
