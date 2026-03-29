# capture/windows.ps1 — Windows screen-region capture stub
#
# STUB: not yet implemented.
#
# Candidate approaches:
#
#   Snipping Tool (built in, Windows 10/11):
#     Start-Process ms-screenskip:   # opens the Snipping Tool UI
#     (no programmatic region-select API; result goes to clipboard)
#     Then retrieve from clipboard:
#       Add-Type -AssemblyName System.Windows.Forms
#       $img = [System.Windows.Forms.Clipboard]::GetImage()
#       $img.Save($env:CAPTURE_OUT, [System.Drawing.Imaging.ImageFormat]::Png)
#
#   PrintScreen to clipboard + PowerShell:
#     Invoke-Expression "& {Add-Type -Assembly System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('%{PRTSC}')}"
#     (captures active window; not interactive region select)
#
#   Greenshot (open source, https://getgreenshot.org/):
#     Has a CLI mode: Greenshot.exe --region $CAPTURE_OUT
#
#   ShareX (open source, https://getsharex.com/):
#     Has a CLI: sharex.exe -capture region -output $CAPTURE_OUT
#     (recommended: most capable, actively maintained)
#
# HOOK: set $env:CLAWXIV_WIN_CAPTURE_TOOL to 'sharex', 'greenshot', or 'clipboard'

param([string]$CaptureOut = $env:CAPTURE_OUT)

if (-not $CaptureOut) {
    $CaptureOut = [System.IO.Path]::Combine($env:TEMP, "clawxiv_capture_$([System.Diagnostics.Process]::GetCurrentProcess().Id).png")
}

$tool = $env:CLAWXIV_WIN_CAPTURE_TOOL
if (-not $tool) { $tool = "stub" }

switch ($tool) {
    "sharex" {
        & sharex.exe -capture region -output $CaptureOut
    }
    "greenshot" {
        & Greenshot.exe --region $CaptureOut
    }
    "clipboard" {
        Write-Host "Press PrtScn or use Snipping Tool, then press Enter..."
        Read-Host
        Add-Type -AssemblyName System.Windows.Forms
        $img = [System.Windows.Forms.Clipboard]::GetImage()
        if ($null -eq $img) {
            Write-Error "No image found in clipboard."
            exit 1
        }
        $img.Save($CaptureOut, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    default {
        Write-Error "capture/windows: STUB not implemented. Set CLAWXIV_WIN_CAPTURE_TOOL to 'sharex', 'greenshot', or 'clipboard'."
        exit 2
    }
}

if (-not (Test-Path $CaptureOut)) { exit 1 }
Write-Output $CaptureOut
