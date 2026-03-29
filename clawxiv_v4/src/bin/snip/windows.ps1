# bin/snip/windows.ps1 — Windows selected-text capture stub
#
# STUB: basic clipboard retrieval implemented; provenance detection is not.
#
# Text retrieval: Get-Clipboard is available on Windows 10+.
# For the PRIMARY selection (highlighted text without Ctrl-C), there is
# no standard Windows API; the closest is to send Ctrl-C programmatically
# via SendKeys, then read the clipboard.
#
# Provenance detection would require querying the foreground window
# (GetForegroundWindow Win32 API) and its associated URL if a browser.
# Browser URL retrieval can be done via UI Automation (accessible via
# the UIAutomation COM object in PowerShell) but is browser-specific.

param()

$prefix = $env:SNIP_TMP_PREFIX
if (-not $prefix) {
    $prefix = [System.IO.Path]::Combine($env:TEMP, "clawxiv_snip_$([System.Diagnostics.Process]::GetCurrentProcess().Id)")
}

$seniorAuthor = $env:CLAWXIV_SENIOR_AUTHOR
if (-not $seniorAuthor) { $seniorAuthor = "András Kornai" }

$author   = $env:CLAWXIV_SNIP_AUTHOR
$url      = $env:CLAWXIV_SNIP_URL
if (-not $author) { $author = $seniorAuthor }
if (-not $url)    { $url = "" }

# ── Optionally send Ctrl-C to copy selection ──────────────────────────────────
if ($env:CLAWXIV_SNIP_COPY_FIRST -ne "0") {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("^c")
    Start-Sleep -Milliseconds 200
}

# ── Read clipboard ────────────────────────────────────────────────────────────
$text = Get-Clipboard -Raw
if ([string]::IsNullOrWhiteSpace($text)) {
    Write-Error "snip/windows: clipboard is empty."
    exit 1
}

# ── TODO: provenance detection ────────────────────────────────────────────────
# Foreground window title and class can be obtained via:
#
# Add-Type @"
# using System;
# using System.Runtime.InteropServices;
# using System.Text;
# public class Win32 {
#     [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
#     [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
# }
# "@
# $hwnd  = [Win32]::GetForegroundWindow()
# $sb    = New-Object System.Text.StringBuilder 256
# [Win32]::GetWindowText($hwnd, $sb, 256) | Out-Null
# $title = $sb.ToString()
# # Map title to author/url...

Write-Warning "snip/windows: provenance detection not yet implemented. Attributed to: $author"

# ── Write output files ────────────────────────────────────────────────────────
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

[System.IO.File]::WriteAllText("$prefix.txt", $text, [System.Text.Encoding]::UTF8)

$meta = @{ author=$author; url=$url; ts=$ts; app="unknown"; bundle="unknown" }
$meta | ConvertTo-Json -Compress | Out-File -Encoding UTF8 "$prefix.meta"
