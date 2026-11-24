#!/bin/bash
# Screenshots of the demo build into docs/design/build-shots/ (debug build, simulator):
#   scripts/screenshots.sh ["iPhone 17"]
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
device=${1:-iPhone 17}
out=$root/docs/design/build-shots
app=$root/build/dd/Build/Products/Debug-iphonesimulator/Pitchside.app
xcodebuild -project "$root/Pitchside.xcodeproj" -scheme Pitchside -destination "platform=iOS Simulator,name=$device" \
  -derivedDataPath "$root/build/dd" build -quiet
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl install "$device" "$app"
mkdir -p "$out"
shot() { # appearance screen name
  xcrun simctl ui "$device" appearance "$1"
  xcrun simctl terminate "$device" com.throwingwood.pitchside 2>/dev/null || true
  xcrun simctl launch "$device" com.throwingwood.pitchside -PitchsideDemo -PitchsideScreen "$2" >/dev/null
  sleep 3
  xcrun simctl io "$device" screenshot "$out/$3-$1.png" >/dev/null 2>&1
  echo "$out/$3-$1.png"
}
for s in home:Home teams:Teams thisgame:ThisGame sheet:Sheet stats:Stats imported:Imported roster:Roster statstab:StatsTab scorer:Scorer; do
  shot light "${s%%:*}" "${s##*:}"
done
for s in home:Home sheet:Sheet scorer:Scorer; do shot dark "${s%%:*}" "${s##*:}"; done
xcrun simctl ui "$device" appearance light
xcrun simctl terminate "$device" com.throwingwood.pitchside 2>/dev/null || true
