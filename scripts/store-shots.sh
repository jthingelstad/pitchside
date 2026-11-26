#!/bin/bash
# The App Store pictures (docs/store): the DEBUG demo games (Pitchside/Demo.swift,
# invented names only) on a 6.9-inch iPhone simulator, the status bar at 9:41 with a
# full battery, light appearance, the whole screen, no words added, no alpha channel.
# The live scorer is landscape (2868 x 1320) and every other picture portrait
# (1320 x 2868). docs/DISTRIBUTION.md "Screenshots".
#
#   scripts/store-shots.sh [<simulator name or UUID>] [<number>...]
#
# With numbers, only those pictures are retaken (e.g. 1 for the scorer). With no
# simulator, the newest iPhone Pro Max simulator. The app is built (Debug, the demo is
# DEBUG only) into build/dd first; STORE_SHOTS_APP=<path to Pitchside.app> skips that.
# The simulator is left running, as it was found or booted; the script shuts nothing down.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

requested="iPhone .* Pro Max"
if [[ $# -gt 0 && ! $1 =~ ^[0-9]+$ ]]; then requested=$1; shift; fi
want=" ${*:-1 2 3 4 5 6} "

device=$(xcrun simctl list -j devices available | python3 -c '
import json, re, sys
runtimes = json.load(sys.stdin)["devices"]
def version(runtime):
    return tuple(int(n) for n in runtime.split("iOS-")[-1].split("-"))
want = sys.argv[1]
phones = [d for r in sorted((r for r in runtimes if ".iOS-" in r), key=version, reverse=True)
          for d in runtimes[r] if d["udid"] == want or re.fullmatch(want, d["name"])]
if not phones: sys.exit("No available simulator matches " + want)
print(next((d for d in phones if d["state"] == "Booted"), phones[0])["udid"])
' "$requested")

app=${STORE_SHOTS_APP:-}
if [[ -z $app ]]; then
  xcodebuild -quiet -project Pitchside.xcodeproj -scheme Pitchside -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
  app=build/dd/Build/Products/Debug-iphonesimulator/Pitchside.app
fi

cleanup() {
  xcrun simctl status_bar "$device" clear >/dev/null 2>&1 || true
  xcrun simctl terminate "$device" com.throwingwood.pitchside >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl install "$device" "$app"
xcrun simctl status_bar "$device" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3
xcrun simctl ui "$device" appearance light

out=build/store-set
mkdir -p "$out" docs/store
# number, name, the demo screen (-PitchsideScreen), seconds to settle. The first three
# are the ones a search result shows: the pitch as the input, the score sheet it
# writes, and the numbers behind it.
shots='1 scorer scorer 5
2 sheet sheet 4
3 stats stats 4
4 games home 4
5 teams teams 4
6 players statstab 4'
echo "$shots" | while read -r n name screen wait; do
  case $want in *" $n "*) ;; *) continue ;; esac
  xcrun simctl launch --terminate-running-process "$device" com.throwingwood.pitchside \
    -PitchsideDemo -PitchsideScreen "$screen" >/dev/null
  sleep "$wait"
  file=$out/iphone-69-$n-$name.png
  xcrun simctl io "$device" screenshot "$file" >/dev/null 2>&1
  swift scripts/flatten-png.swift "$file"
  size=$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixel/ {print $2}' | paste -sd x -)
  case $size in
    1320x2868 | 2868x1320 | 1290x2796 | 2796x1290 | 1260x2736 | 2736x1260) ;;
    *) echo "$file is $size, not a 6.9-inch size: use a 6.9-inch simulator" >&2; exit 1 ;;
  esac
  # one picture a number: an earlier set's picture under another name goes
  find docs/store -name "iphone-69-$n-*.png" ! -name "iphone-69-$n-$name.png" -exec rm {} +
  cp "$file" "docs/store/iphone-69-$n-$name.png"
  echo "docs/store/iphone-69-$n-$name.png ($size)"
done
# pictures the set no longer has
for f in docs/store/iphone-69-*.png; do
  [[ -e $f ]] || continue
  n=$(basename "$f" | sed -E 's/^iphone-69-([0-9]+)-.*/\1/')
  echo "$shots" | grep -q "^$n " || { rm "$f"; echo "removed $f"; }
done
