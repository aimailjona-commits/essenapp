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

shoot() {  # $1 = Screen, $2 = Dateiname, danach weitere App-Argumente (z. B. -demoAppearance dark)
  local screen=$1 file=$2; shift 2
  xcrun simctl terminate "$udid" de.jsenf.essenapp 2>/dev/null || true
  xcrun simctl launch "$udid" de.jsenf.essenapp -demoScreen "$screen" "$@" >/dev/null
  sleep 5
  xcrun simctl io "$udid" screenshot "$out/$file.png" >/dev/null
}

xcrun simctl ui "$udid" appearance light
for s in onboarding start quick generator generating offers offer stores plan recipe cooking sharecard recipes myrecipe recipeform shopping list pantry settings profile notifications instagram imported importlink sharepair shareimport shareresult fridgecam fridgereview cooknow offline voiceadd storeask substitute nomood guests leftovers basics variety watch scanner nextweek offerstock savings budgetover singlestore wallet bonus coupon couponadd spending achievements unlock review reviews recipelink sharedrecipe widgetsetup widget liveactivity empty; do shoot "$s" "$s"; done
# Dark Mode (68): Simulator dunkel (Einstellung „System“) und zusätzlich per Demo-Argument erzwungen
xcrun simctl ui "$udid" appearance dark
for s in onboarding start quick generator offers offer stores plan recipe cooking sharecard recipes myrecipe recipeform shopping list pantry settings profile notifications instagram imported importlink sharepair shareresult fridgecam fridgereview cooknow offline voiceadd storeask substitute nomood guests leftovers basics variety watch scanner nextweek offerstock savings budgetover singlestore wallet bonus coupon couponadd spending achievements unlock review reviews recipelink sharedrecipe widgetsetup widget liveactivity; do
  shoot "$s" "dark-$s" -demoAppearance dark
done
xcrun simctl ui "$udid" appearance light
ls -la "$out"
