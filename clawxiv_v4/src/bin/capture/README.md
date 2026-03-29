# capture — platform-dispatching screen-region capture

## Purpose

`capture.sh` provides a single entry point for interactive screen-region
capture across platforms.  It detects the host environment and delegates to
the appropriate platform implementation, each of which is a self-contained
script in this directory.

The output is always a PNG file whose path is printed to stdout and also
available via `$CAPTURE_OUT`.

## Usage

```sh
# Use defaults (output to /tmp/clawxiv_capture_$$.png)
./capture.sh

# Specify output path
CAPTURE_OUT=~/myproject/src/fig/diagram.png ./capture.sh

# Override platform detection (for testing stubs)
CLAWXIV_PLATFORM=linux_x11 ./capture.sh
```

## Platform implementations

| File               | Platform       | Status      | Primary tool       |
|--------------------|----------------|-------------|--------------------|
| `macos.sh`         | macOS          | Implemented | `screencapture -i` |
| `linux_x11.sh`     | Linux / X11    | Stub        | flameshot / scrot  |
| `linux_wayland.sh` | Linux / Wayland| Stub        | grim + slurp       |
| `windows.ps1`      | Windows        | Stub        | ShareX / Greenshot |

## Adding a new platform

1. Create `<platform>.sh` (or `.ps1`) in this directory.
2. The script must:
   - Read `$CAPTURE_OUT` for the output path.
   - Write a valid PNG to that path.
   - Print the output path to stdout on success.
   - Exit 0 on success, 1 on user cancel, 2 on unsupported, 3 on missing tool.
3. Add a `case` branch in `capture.sh`.
4. Add a row to the table above.
5. Document any required tools under "Platform notes" below.

## Platform notes

### macOS
`screencapture` is a standard macOS utility present on all installations since
10.2.  No additional software is required.  The `-i` flag presents the
familiar crosshair cursor.

To bind the full `clawxiv fig-capture` workflow to a keyboard shortcut, see
`bin/fig-capture` and the "User Guide" section of the ClawXiv whitepaper.

### Linux / X11
`flameshot` is the recommended tool: it has a polished UI, is packaged in
most distributions, and supports both X11 and XWayland.  `scrot` and
ImageMagick's `import` are fallbacks.

### Linux / Wayland
`grim` with `slurp` is the canonical choice for wlroots-based compositors
(sway, river, Hyprland).  GNOME Shell users should use `gnome-screenshot`.
XWayland users may use the X11 implementations.

### Windows
ShareX (https://getsharex.com) is the recommended open-source tool.
Greenshot (https://getgreenshot.org) is an alternative.  A clipboard-based
fallback is also provided for environments where neither is installed.

## Exit codes

| Code | Meaning                                      |
|------|----------------------------------------------|
| 0    | Capture successful; path written to stdout   |
| 1    | User cancelled (Escape or equivalent)        |
| 2    | Platform not supported or not detected       |
| 3    | Required capture tool not found              |
