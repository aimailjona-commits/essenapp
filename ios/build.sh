#!/bin/bash
# In WSL: ./build.sh            → bauen, signieren, aufs iPhone (xtool dev)
#         ./build.sh build      → nur bauen
# Gebaut wird in ~/build/essenapp-ios, weil xtool auf /mnt/c an Dateirechten scheitert (E24).
set -e
src="$(cd "$(dirname "$0")" && pwd)"
dst="$HOME/build/essenapp-ios"
mkdir -p "$dst"
rsync -a --delete --exclude .build --exclude xtool --exclude tools "$src/" "$dst/"
cd "$dst"
xtool dev "${1:-run}"
