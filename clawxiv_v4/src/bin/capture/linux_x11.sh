#!/usr/bin/env bash
# capture/linux_x11.sh — Linux/X11 screen-region capture stub
#
# STUB: not yet implemented.
#
# Candidate tools (in preference order):
#   flameshot   https://flameshot.org/  (GUI, supports region selection,
#               widely packaged, works on X11 and Wayland with XWayland)
#               flameshot gui --raw > "$CAPTURE_OUT"
#
#   scrot       https://github.com/resurrecting-open-source-projects/scrot
#               scrot --select "$CAPTURE_OUT"
#
#   import      from ImageMagick; available everywhere ImageMagick is.
#               import "$CAPTURE_OUT"
#
# To implement: uncomment and test one of the blocks below, then remove
# this notice and the exit 2 line.
#
# HOOK: set CLAWXIV_X11_CAPTURE_TOOL to override autodetection.

set -euo pipefail

CAPTURE_OUT="${CAPTURE_OUT:-/tmp/clawxiv_capture_$$.png}"
TOOL="${CLAWXIV_X11_CAPTURE_TOOL:-auto}"

if [ "$TOOL" = "auto" ]; then
    if command -v flameshot &>/dev/null; then TOOL=flameshot
    elif command -v scrot    &>/dev/null; then TOOL=scrot
    elif command -v import   &>/dev/null; then TOOL=import
    else TOOL=none
    fi
fi

case "$TOOL" in
    flameshot)
        flameshot gui --raw > "$CAPTURE_OUT"
        ;;
    scrot)
        scrot --select "$CAPTURE_OUT"
        ;;
    import)
        import "$CAPTURE_OUT"
        ;;
    none|*)
        echo "capture/linux_x11: no supported capture tool found." >&2
        echo "Install flameshot, scrot, or ImageMagick." >&2
        exit 3
        ;;
esac

[ -f "$CAPTURE_OUT" ] || exit 1
echo "$CAPTURE_OUT"
