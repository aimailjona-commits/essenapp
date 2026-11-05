#!/bin/bash
# In WSL: ./build.sh            → bauen, signieren, aufs iPhone (xtool dev)
#         ./build.sh build      → nur bauen
# Gebaut wird in ~/build/essenapp-ios, weil xtool auf /mnt/c an Dateirechten scheitert (E24).
set -e
src="$(cd "$(dirname "$0")" && pwd)"
dst="${BUILD_DIR:-$HOME/build/essenapp-ios}"
# rsync --delete nur in ~/build/<name> – ein leerer/falscher Pfad hat sonst / gelöscht (Vorfall 2026-11-05)
case "$dst" in *..*) false ;; "$HOME"/build/[!/]*) [ -n "$HOME" ] ;; *) false ;; esac || { echo "build.sh: BUILD_DIR muss unter \$HOME/build/ liegen: '$dst'" >&2; exit 1; }
mkdir -p "$dst"
rsync -a --delete --exclude .build --exclude xtool --exclude tools "$src/" "$dst/"
cd "$dst"
# iPhone hängt an Windows (Apple Devices), WSL spricht dessen usbmux-Dienst über das Gateway an (E33)
export USBMUXD_SOCKET_ADDRESS="${USBMUXD_SOCKET_ADDRESS:-$(ip route list default | awk '{print $3}'):27015}"
xtool dev "${1:-run}"
# App-Intents-Index passt zu den gerade gebauten Intents? Sonst tun Widget-Konfiguration und Abhak-Knopf nichts (E83)
python3 "$src/tools/appintents_index.py" --check || echo "WARNUNG: python3 tools/appintents_index.py ausführen und neu bauen"
