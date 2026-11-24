#!/bin/bash
# The Kubb Engine, vendored from one tagged release of kubb-engine
# (jthingelstad/kubb-engine), byte for byte, as the engine's own docs ask (its
# docs/VERSIONING.md "Releases and vendoring"). Pitchside carries one engine, the
# release named by TAG below, the way throwingwood-ios carries its newest:
#
#   PitchsideKit/Sources/KubbEngine/Engine/   core/, pitch/, session/, tune/,
#       version.lua, engine.json (the engine's manifest: its version and a sha256
#       for every Lua file) and LICENSE
#   PitchsideKit/Tests/KubbEngineTests/Fixtures/golden/   the release's golden
#       driver and corpus (tests/golden/drive.lua and hashes.json), the hashes its
#       reference platform gives, which the tests here must match
#
#   scripts/vendor-engine.sh sync    copy them from the kubb-engine checkout beside
#                                    this repo (KUBB_ENGINE_SOURCE overrides) at TAG:
#                                    the tag's tree, never the working tree; the
#                                    checkout is only read
#   scripts/vendor-engine.sh check   the vendored copy is the release TAG names: every
#                                    Lua file as its engine.json says (sha256), byte
#                                    for byte, none missing or extra, and the corpus
#                                    recorded by this engine version. Needs no
#                                    kubb-engine checkout
#
# To move to a new release: change TAG, run sync, then the tests (AGENTS.md). Never
# edit the vendored files; a fix goes into kubb-engine, is tagged, then synced here.

set -euo pipefail

# The one engine Pitchside carries.
TAG=v1.0.0

root=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${KUBB_ENGINE_SOURCE:-$root/../kubb-engine}
engine=$root/PitchsideKit/Sources/KubbEngine/Engine
golden=$root/PitchsideKit/Tests/KubbEngineTests/Fixtures/golden

engine_paths=(core pitch session tune version.lua engine.json LICENSE)
golden_files=(drive.lua hashes.json)

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# engine.json's "files" map as "<path> <sha256>" lines (written one entry a line by
# the engine's tools/manifest.mjs).
manifest_files() {
  sed -nE '/^  "files": \{/,/^  \}/s/^ *"([^"]+\.lua)": "([0-9a-f]{64})",?$/\1 \2/p' "$engine/engine.json"
}

json_version() {
  sed -nE 's/^ *"version": "([^"]+)",?$/\1/p' "$1" | head -1
}

status=0
fail() { echo "$*" >&2; status=1; }

case "${1:-}" in
  sync)
    commit=$(git -C "$source_dir" rev-parse --verify --quiet "$TAG^{commit}") || {
      echo "$source_dir has no tag $TAG; fetch its tags first (git -C $source_dir fetch --tags)." >&2
      exit 1
    }
    rm -rf "$engine" "$golden"
    mkdir -p "$engine" "$golden"
    count=0
    while IFS= read -r path; do
      mkdir -p "$engine/$(dirname "$path")"
      git -C "$source_dir" cat-file blob "$commit:$path" > "$engine/$path"
      count=$((count + 1))
    done < <(git -C "$source_dir" ls-tree -r --name-only "$commit" -- "${engine_paths[@]}")
    for f in "${golden_files[@]}"; do
      git -C "$source_dir" cat-file blob "$commit:tests/golden/$f" > "$golden/$f"
    done
    echo "vendored kubb-engine $TAG (${commit:0:7}): $count files, and the golden driver and corpus"
    exec "$0" check
    ;;
  check)
    [[ -f $engine/engine.json ]] || { echo "no Engine/engine.json; run sync" >&2; exit 1; }
    version=$(json_version "$engine/engine.json")
    [[ "v$version" == "$TAG" ]] || fail "engine.json is version $version, TAG is $TAG; run sync"
    count=0
    while read -r name want; do
      count=$((count + 1))
      if [[ ! -f $engine/$name ]]; then
        fail "missing: $name"
      elif [[ $(sha "$engine/$name") != "$want" ]]; then
        fail "changed: $name (vendored files are never edited; fix it in kubb-engine and move to its next tag)"
      fi
    done < <(manifest_files)
    [[ $count -gt 0 ]] || fail "engine.json names no files"
    while IFS= read -r f; do
      name=${f#"$engine"/}
      case $name in engine.json | LICENSE) continue ;; esac
      manifest_files | grep -q "^$name " || fail "extra: $name (not in engine.json)"
    done < <(find "$engine" -type f | LC_ALL=C sort)
    [[ -s $engine/LICENSE ]] || fail "missing: LICENSE"
    for f in "${golden_files[@]}"; do [[ -s $golden/$f ]] || fail "missing: golden/$f"; done
    corpus=$(json_version "$golden/hashes.json" 2>/dev/null || true)
    [[ $corpus == "$version" ]] || fail "golden corpus is ${corpus:-missing}, expected $version; run sync"
    if [[ $status == 0 ]]; then
      echo "kubb-engine $TAG: $count files match engine.json, golden corpus recorded by $corpus"
    fi
    exit $status
    ;;
  *)
    echo "usage: scripts/vendor-engine.sh sync | check" >&2
    exit 64
    ;;
esac
