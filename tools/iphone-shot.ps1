# Startet die App auf dem echten iPhone (optional in einem Demo-Screen) und macht einen Screenshot.
# Voraussetzung: Admin-PowerShell mit `python -m pymobiledevice3 remote tunneld` läuft, iPhone entsperrt (E34).
# Aufruf: .\tools\iphone-shot.ps1 [-Screen start] [-Name datei]   (ohne -Screen: aktueller Bildschirm)
param([string]$Screen = "", [string]$Name = "iphone")

$udid = "00008101-001515A03A29003A"
$out = Join-Path $PSScriptRoot "..\.debug"
New-Item -ItemType Directory -Force $out | Out-Null

if ($Screen) {
    python -m pymobiledevice3 developer dvt launch --tunnel $udid "de.jsenf.essenapp -demoScreen $Screen" | Out-Null
    Start-Sleep -Seconds 4
}
python -m pymobiledevice3 developer dvt screenshot --tunnel $udid (Join-Path $out "$Name.png")
Write-Host (Resolve-Path (Join-Path $out "$Name.png"))
