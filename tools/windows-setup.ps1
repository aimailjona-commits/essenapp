# Als Administrator ausführen. Nach jedem Windows-/WSL-Neustart erneut, weil sich die WSL-IP ändert (E33).
# 1. iPhone nicht mehr per usbipd an WSL (xtool hängt sonst bei "Connecting"), sondern über Apples Dienst unter Windows.
# 2. WSL erreicht Apples usbmux-Dienst (127.0.0.1:27015) über die WSL-Gateway-IP.
# 3. iPhone im WLAN erreicht das Backend in WSL über <Windows-IP>:8000.
$usbipd = Get-Command usbipd -ErrorAction SilentlyContinue
if ($usbipd) {
    # usbipd schreibt Infos nach stderr; über cmd aufrufen, damit PowerShell 5.1 das nicht als Fehler wertet
    $apple = (& usbipd list) | Select-String "05ac:" | ForEach-Object { ($_ -split "\s+")[0] } | Where-Object { $_ -match "^\d+-\d+$" }
    foreach ($busid in $apple) { cmd /c "usbipd detach --busid $busid 2>nul & usbipd unbind --busid $busid 2>nul" }
}

$ErrorActionPreference = "Stop"

$gateway = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "vEthernet (WSL*)").IPAddress | Select-Object -First 1
$wslIp = ((wsl -d Ubuntu-24.04 -- hostname -I) -split " ")[0]

netsh interface portproxy set v4tov4 listenport=27015 listenaddress=$gateway connectport=27015 connectaddress=127.0.0.1
netsh interface portproxy set v4tov4 listenport=8000 listenaddress=0.0.0.0 connectport=8000 connectaddress=$wslIp

if (-not (Get-NetFirewallRule -DisplayName "Essenapp WSL usbmux" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Essenapp WSL usbmux" -Direction Inbound -InterfaceAlias "vEthernet (WSL (Hyper-V firewall))" -Protocol TCP -LocalPort 27015 -Action Allow | Out-Null
}
if (-not (Get-NetFirewallRule -DisplayName "Essenapp Backend" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Essenapp Backend" -Direction Inbound -Protocol TCP -LocalPort 8000 -RemoteAddress LocalSubnet -Action Allow | Out-Null
}

netsh interface portproxy show v4tov4
Write-Host "Gateway fuer WSL: $gateway  |  WSL-IP: $wslIp"
