#!/usr/bin/env bash
# capture/linux_wayland.sh — Linux/Wayland screen-region capture stub
#
# STUB: not yet implemented.
#
# Candidate tools:
#   grim + slurp   compositors: sway, river, and other wlroots compositors
#                  slurp selects a region; grim captures it.
#                  REGION=$(slurp) && grim -g "$REGION" "$CAPTURE_OUT"
#
#   gnome-screenshot   for GNOME Shell on Wayland (requires portal support)
#                  gnome-screenshot -a -f "$CAPTURE_OUT"
#
#   flameshot      works under XWayland; native Wayland support varies by
#                  compositor.
#
# HOOK: set CLAWXIV_WAYLAND_CAPTURE_TOOL to override autodetection.

set -euo pipefail

CAPTURE_OUT="${CAPTURE_OUT:-/tmp/clawxiv_capture_$$.png}"
TOOL="${CLAWXIV_WAYLAND_CAPTURE_TOOL:-auto}"

if [ "$TOOL" = "auto" ]; then
    if command -v grim &>/dev/null && command -v slurp &>/dev/null; then TOOL=grim
    elif command -v gnome-screenshot &>/dev/null; then TOOL=gnome
    elif command -v flameshot        &>/dev/null; then TOOL=flameshot
    else TOOL=none
    fi
fi

case "$TOOL" in
    grim)
        REGION=$(slurp) || exit 1
        grim -g "$REGION" "$CAPTURE_OUT"
        ;;
    gnome)
        gnome-screenshot -a -f "$CAPTURE_OUT"
        ;;
    flameshot)
        flameshot gui --raw > "$CAPTURE_OUT"
        ;;
    none|*)
        echo "capture/linux_wayland: no supported capture tool found." >&2
        echo "Install grim+slurp (wlroots), gnome-screenshot, or flameshot." >&2
        exit 3
        ;;
esac

[ -f "$CAPTURE_OUT" ] || exit 1
echo "$CAPTURE_OUT"
