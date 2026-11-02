#!/bin/bash
# Auf macOS (CI): App im Simulator starten und jeden Demo-Screen fotografieren.
# Aufruf: ios/tools/screenshots.sh <derivedDataPath> <ausgabeordner>
set -euo pipefail
derived=$1; out=$2; mkdir -p "$out"
app=$(find "$derived/Build/Products" -path '*iphonesimulator*' -name '*.app' -maxdepth 3 | head -1)
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
phones = [x for rt in sorted(d, reverse=True) if "iOS" in rt for x in d[rt] if x["name"].startswith("iPhone")]
pick = next((x for x in phones if "Pro" in x["name"] and "Max" not in x["name"]), phones[0])
print(pick["udid"]); print(pick["name"], file=sys.stderr)')
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 || true
xcrun simctl install "$udid" "$app"

shoot() {  # $1 = Screen, $2 = Dateiname
  xcrun simctl terminate "$udid" de.jsenf.essenapp 2>/dev/null || true
  xcrun simctl launch "$udid" de.jsenf.essenapp -demoScreen "$1" >/dev/null
  sleep 5
  xcrun simctl io "$udid" screenshot "$out/$2.png" >/dev/null
}

xcrun simctl ui "$udid" appearance light
for s in onboarding start quick generator generating offers offer stores plan recipe cooking sharecard shopping list pantry settings profile notifications empty; do shoot "$s" "$s"; done
xcrun simctl ui "$udid" appearance dark  # App erzwingt hell (E15) – Kontrolle, dass nichts weiß auf weiß wird
for s in start; do shoot "$s" "dark-$s"; done
ls -la "$out"
