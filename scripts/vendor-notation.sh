#!/bin/bash
# Planet Kubb Notation's reader, vendored from one tagged release of pk-kubb-score
# (Planet-Kubb/pk-kubb-score), byte for byte, as kubb-engine's `make sync-notation`
# does into its tests/vendor/pk-kubb-score/. Pitchside runs these files in
# JavaScriptCore (PitchsideKit/Sources/Notation/Reader.swift) for every score sheet and
# every stat, so the numbers are the reader's own, never re-derived in Swift:
#
#   PitchsideKit/Sources/Notation/Vendor/notation-parser.js   the grammar's parser (Peggy)
#   PitchsideKit/Sources/Notation/Vendor/canonical.js         the canonical writer
#   PitchsideKit/Sources/Notation/Vendor/kubb.js              the tolerant reader and scorer
#   PitchsideKit/Sources/Notation/Vendor/SOURCE               the tag and its commit
#   PitchsideKit/Sources/Notation/Vendor/SHA256SUMS           each file's sha256 at the tag
#
#   scripts/vendor-notation.sh sync    copy them from the pk-kubb-score checkout beside
#                                      this repo (PK_KUBB_SCORE overrides) at PKTAG: the
#                                      tag's tree, never the working tree
#   scripts/vendor-notation.sh check   every file is as SHA256SUMS says, and (when the
#                                      checkout is there) as the tag has it
#
# Never edit the copies. A change to the notation goes into pk-kubb-score (grammar,
# docs/notation-2.md and a conformance case together), gets an edition tag, then a sync.

set -euo pipefail

# The one notation edition Pitchside reads with.
PKTAG=v2-2026.11

root=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${PK_KUBB_SCORE:-$root/../pk-kubb-score}
vendor=$root/PitchsideKit/Sources/Notation/Vendor
files=(notation-parser.js canonical.js kubb.js)

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
status=0
fail() { echo "$*" >&2; status=1; }

case "${1:-}" in
  sync)
    commit=$(git -C "$source_dir" rev-parse --verify --quiet "$PKTAG^{commit}") || {
      echo "$source_dir has no tag $PKTAG; fetch its tags first." >&2
      exit 1
    }
    mkdir -p "$vendor"
    : > "$vendor/SHA256SUMS"
    for f in "${files[@]}"; do
      git -C "$source_dir" cat-file blob "$commit:site/assets/$f" > "$vendor/$f"
      echo "$(sha "$vendor/$f")  $f" >> "$vendor/SHA256SUMS"
    done
    printf '%s\n%s\n' "$PKTAG" "$commit" > "$vendor/SOURCE"
    echo "vendored pk-kubb-score $PKTAG (${commit:0:7}): ${files[*]}"
    exec "$0" check
    ;;
  check)
    [[ -s $vendor/SOURCE && -s $vendor/SHA256SUMS ]] || { echo "nothing vendored; run sync" >&2; exit 1; }
    [[ $(head -1 "$vendor/SOURCE") == "$PKTAG" ]] || fail "SOURCE names $(head -1 "$vendor/SOURCE"), PKTAG is $PKTAG; run sync"
    for f in "${files[@]}"; do
      want=$(awk -v f="$f" '$2 == f { print $1 }' "$vendor/SHA256SUMS")
      [[ -n $want ]] || { fail "SHA256SUMS has no $f"; continue; }
      [[ -f $vendor/$f ]] || { fail "missing: $f"; continue; }
      [[ $(sha "$vendor/$f") == "$want" ]] || fail "changed: $f (never edit the copies)"
    done
    commit=$(sed -n 2p "$vendor/SOURCE")
    if git -C "$source_dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
      tagged=$(git -C "$source_dir" rev-parse --verify --quiet "$PKTAG^{commit}" || true)
      [[ $tagged == "$commit" ]] || fail "SOURCE's commit is not $PKTAG in $source_dir"
      for f in "${files[@]}"; do
        [[ $(git -C "$source_dir" cat-file blob "$commit:site/assets/$f" | shasum -a 256 | cut -d' ' -f1) == $(sha "$vendor/$f") ]] ||
          fail "$f differs from $PKTAG's"
      done
    fi
    [[ $status == 0 ]] && echo "pk-kubb-score $PKTAG: ${#files[@]} files match"
    exit $status
    ;;
  *)
    echo "usage: scripts/vendor-notation.sh sync | check" >&2
    exit 64
    ;;
esac
