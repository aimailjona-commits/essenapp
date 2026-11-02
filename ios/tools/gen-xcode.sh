#!/bin/bash
# In WSL: erzeugt das Xcode-Projekt für den Cloud-Simulator (CI) und legt es unter ios/xtool/ ab.
# Nach Änderungen an xtool.yml, Info.plist oder Icon erneut ausführen und committen.
set -e
src="$(cd "$(dirname "$0")/.." && pwd)"
dst="$HOME/build/essenapp-ios"
rsync -a --delete --exclude .build --exclude xtool --exclude tools "$src/" "$dst/"
cd "$dst" && xtool dev generate-xcode-project
rm -rf "$src/xtool" && mkdir -p "$src/xtool/.xtool-tmp"
cp -r xtool/Essenapp.xcworkspace "$src/xtool/"
cp -r xtool/.xtool-tmp/Essenapp.xcodeproj xtool/.xtool-tmp/Essenapp "$src/xtool/.xtool-tmp/"
