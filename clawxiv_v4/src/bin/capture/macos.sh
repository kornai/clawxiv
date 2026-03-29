#!/usr/bin/env bash
# capture/macos.sh — macOS screen-region capture via screencapture(1)
#
# Requires: screencapture (present on all macOS installations since 10.2)
# Tested on: macOS Tahoe 26.x (M-series), macOS Sequoia 15.x (Intel/M-series)
#
# Interactive mode: presents the standard crosshair region-selection cursor
# (same UI as Shift-Cmd-4).  User presses Escape to cancel.
#
# Flags used:
#   -i   interactive selection mode
#   -x   suppress shutter sound
#   -t png  force PNG output regardless of filename extension

set -euo pipefail

CAPTURE_OUT="${CAPTURE_OUT:-/tmp/clawxiv_capture_$$.png}"

# screencapture exits 0 even on Escape but does NOT create the file.
/usr/sbin/screencapture -ixt png "$CAPTURE_OUT"

if [ ! -f "$CAPTURE_OUT" ]; then
    # User pressed Escape or otherwise cancelled.
    exit 1
fi

echo "$CAPTURE_OUT"
