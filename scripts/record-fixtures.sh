#!/bin/bash
# Remakes PitchsideKit/Tests/PitchsideModelTests/Fixtures/record-games.json from the
# kubb-engine tag this app vendors: its record-mode games (tests/fixtures/record/games.lua),
# each with the file and warnings the engine's own record.build gives on desktop Lua 5.4.
# Reads the sibling kubb-engine checkout through `git archive` into a temporary folder;
# writes nothing there.
#   scripts/record-fixtures.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
engine=${KUBB_ENGINE:-$root/../kubb-engine}
tag=$(sed -n 's/^TAG=//p' "$root/scripts/vendor-engine.sh")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$engine" archive "$tag" | tar -x -C "$tmp"
out=$root/PitchsideKit/Tests/PitchsideModelTests/Fixtures/record-games.json
lua5.4 "$root/scripts/record-fixtures.lua" "$tmp" |
  python3 -c 'import json,sys; json.dump(json.load(sys.stdin), sys.stdout, indent=1, sort_keys=True, ensure_ascii=False)' >"$out"
echo "$out ($tag)"
