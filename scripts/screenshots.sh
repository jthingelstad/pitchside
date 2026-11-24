#!/bin/bash
# Run the scoring journeys on an iPhone simulator and save their actual screen captures.
# With no --scorer option also refresh the other demo screens.
#   scripts/screenshots.sh [--scorer] ["iPhone 17" | simulator-UUID]
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scorer_only=false
if [[ ${1:-} == --scorer ]]; then scorer_only=true; shift; fi
requested=${1:-iPhone 17}
device=$(xcrun simctl list -j devices available | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
def version(runtime):
    return tuple(int(n) for n in runtime.split("iOS-")[-1].split("-"))
phones = [d for r in sorted((r for r in runtimes if ".iOS-" in r), key=version, reverse=True)
          for d in runtimes[r] if d["name"] == sys.argv[1] or d["udid"] == sys.argv[1]]
if not phones: sys.exit("No available simulator matches " + sys.argv[1])
print(next((d for d in phones if d["state"] == "Booted"), phones[0])["udid"])
' "$requested")
scratch=$(mktemp -d)
cleanup() {
  result=$?
  xcrun simctl ui "$device" appearance light >/dev/null 2>&1 || true
  xcrun simctl status_bar "$device" clear >/dev/null 2>&1 || true
  xcrun simctl terminate "$device" com.throwingwood.pitchside >/dev/null 2>&1 || true
  if [[ $result == 0 ]]; then
    rm -rf "$scratch"
  else
    echo "Simulator test results are in $scratch" >&2
  fi
}
trap cleanup EXIT
out="$root/docs/design/build-shots"
mkdir -p "$out"
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl status_bar "$device" override --time '9:41'
xcrun simctl ui "$device" appearance light
xc=(xcodebuild -quiet -project "$root/Pitchside.xcodeproj" -scheme Pitchside
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$root/build/dd"
    -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO)
dark_test=PitchsideUITests/ScoringTests/testMarkedPitchInSystemAppearance
"${xc[@]}" -resultBundlePath "$scratch/scoring.xcresult" "-skip-testing:$dark_test" test
xcrun xcresulttool export attachments --path "$scratch/scoring.xcresult" --output-path "$scratch/shots" >/dev/null
xcrun simctl ui "$device" appearance dark
"${xc[@]}" -resultBundlePath "$scratch/dark.xcresult" "-only-testing:$dark_test" test
xcrun xcresulttool export attachments --path "$scratch/dark.xcresult" --output-path "$scratch/dark" >/dev/null
python3 - "$scratch/shots" "$scratch/dark" "$out" <<'PY'
import json, pathlib, shutil, sys
source, dark, output = map(pathlib.Path, sys.argv[1:])
expected = {"Scorer-light", "Inkast-light", "Baton-marked-light", "Who-threw-light",
            "Thrown-from-light", "King-shot-light", "Sideline-light", "Scorer-dark", "Timeline-edit-light", "Printable-score-sheet", "Zoomed-cluster"}
shots = {a["suggestedHumanReadableName"].split("_")[0]: folder / a["exportedFileName"]
         for folder in (source, dark) for test in json.loads((folder / "manifest.json").read_text()) for a in test["attachments"]}
missing = (expected | {"Scored-game"}) - shots.keys()
if missing: sys.exit("Missing simulator attachments: " + str(missing))
for name in sorted(expected):
    print(shutil.copyfile(shots[name], output / (name + ".png")))
shutil.copyfile(shots["Scored-game"], source / "game.txt")
PY
node --input-type=module - "$root" "$scratch/shots/game.txt" <<'JS'
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const [root, file] = process.argv.slice(2);
const { analyze } = await import(pathToFileURL(root + "/PitchsideKit/Sources/Notation/Vendor/kubb.js"));
const { winner, winHow, endTurn, warnings, turnWarnings } = analyze(readFileSync(file, "utf8"));
assert.deepEqual({ winner, winHow, endTurn, warnings, turnWarnings },
                 { winner: "A", winHow: "king", endTurn: 5, warnings: [], turnWarnings: 0 });
console.log("Simulator export read back: Team A, king down in turn 5, zero warnings.");
JS
for suite in scoring dark; do
  xcrun xcresulttool get test-results summary --path "$scratch/$suite.xcresult" |
    python3 -c 'import json,sys; print("Simulator tests passed:", json.load(sys.stdin)["passedTests"])'
done
if [[ $scorer_only == false ]]; then
  shot() {
    xcrun simctl ui "$device" appearance "$1"
    xcrun simctl terminate "$device" com.throwingwood.pitchside 2>/dev/null || true
    xcrun simctl launch "$device" com.throwingwood.pitchside -PitchsideDemo -PitchsideScreen "$2" >/dev/null
    sleep 3
    xcrun simctl io "$device" screenshot "$out/$3-$1.png" >/dev/null
  }
  for s in home:Home teams:Teams thisgame:ThisGame sheet:Sheet stats:Stats imported:Imported roster:Roster statstab:StatsTab; do
    shot light "${s%%:*}" "${s##*:}"
  done
  for s in home:Home sheet:Sheet; do shot dark "${s%%:*}" "${s##*:}"; done
fi
