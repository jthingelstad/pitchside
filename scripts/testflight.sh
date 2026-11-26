#!/bin/bash
# Archives Pitchside for the App Store and uploads it to TestFlight, for the Dev
# (internal) group only by default (Config/ExportOptions-TestFlight.plist). Builds come
# from a clean commit on main: Apple's build number is the commit count
# (scripts/version.sh), so it only goes up and a commit uploads once.
#
#   scripts/testflight.sh               internal testers only
#   scripts/testflight.sh --external    a build the Beta group and the App Store can take,
#                                       once Apple's review passes it
#   scripts/testflight.sh --dry-run     the checks and the plan, nothing built or sent
#   scripts/testflight.sh --unsigned    a Release archive for a phone, unsigned, never
#                                       exported or sent (checks the archive builds)
#
# --dry-run and --unsigned go with either of the first two. Every upload is Jamie's call
# (docs/DISTRIBUTION.md).
#
# Needs the team in Config/Signing.local.xcconfig and, from a shell without Xcode's
# sign-in, an App Store Connect API key: a team key with the Admin role, its
# AuthKey_<key id>.p8 in ~/.appstoreconnect/private_keys, and its ids in
# Config/AppStoreConnect.local. Git ignores both files:
#   DEVELOPMENT_TEAM = <team id>          (Config/Signing.local.xcconfig)
#   ASC_KEY_ID=<key id>                   (Config/AppStoreConnect.local)
#   ASC_ISSUER_ID=<issuer id>
# Throwing Wood's two files are the same team and key, so copying them over works.
#
# Signing is automatic and takes the project's own settings, entitlements included
# (CODE_SIGN_ENTITLEMENTS, when the target has one), so nothing here names a capability.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

options=Config/ExportOptions-TestFlight.plist
external="" dry="" unsigned=""
for arg in "$@"; do
  case $arg in
    --external) external=1 ;;
    --dry-run) dry=1 ;;
    --unsigned) unsigned=1 ;;
    *) echo "Usage: scripts/testflight.sh [--external] [--dry-run] [--unsigned]" >&2; exit 64 ;;
  esac
done

version=$(scripts/version.sh)
build=$(git rev-list --count HEAD)
commit=$(git rev-parse --short HEAD)

if [[ -z $unsigned ]] &&
  ! grep -qE '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}' Config/Signing.local.xcconfig 2>/dev/null; then
  echo "Put DEVELOPMENT_TEAM = <your team ID> in Config/Signing.local.xcconfig first." >&2
  exit 1
fi
if [[ -n $(git status --porcelain) ]]; then
  echo "The checkout has changes. TestFlight builds come from a clean commit." >&2
  exit 1
fi
git fetch -q origin main
if ! git merge-base --is-ancestor HEAD origin/main; then
  echo "This commit isn't on main. TestFlight builds come from main." >&2
  exit 1
fi

auth=()
if [[ -z $unsigned && -f Config/AppStoreConnect.local ]]; then
  key_id=$(sed -nE 's/^ASC_KEY_ID=([A-Z0-9]+)$/\1/p' Config/AppStoreConnect.local)
  issuer=$(sed -nE 's/^ASC_ISSUER_ID=([0-9a-f-]+)$/\1/p' Config/AppStoreConnect.local)
  key=$HOME/.appstoreconnect/private_keys/AuthKey_$key_id.p8
  if [[ -z $key_id || -z $issuer || ! -f $key ]]; then
    echo "Config/AppStoreConnect.local needs ASC_KEY_ID and ASC_ISSUER_ID, and the key in ~/.appstoreconnect/private_keys." >&2
    exit 1
  fi
  auth=(-authenticationKeyPath "$key" -authenticationKeyID "$key_id" -authenticationKeyIssuerID "$issuer")
fi

out=$root/build/testflight/$version-$build
audience="the Dev group only"
[[ -n $external ]] && audience="the Dev group, and the Beta group and the App Store once Apple's review passes it"
echo "Pitchside $version, build $build ($commit), for $audience"
echo "Archive and export in ${out#"$root"/}"
if [[ -n $unsigned ]]; then
  echo "Unsigned: archive only, nothing exported or sent."
elif [[ ${#auth[@]} -gt 0 ]]; then
  echo "Signing with the App Store Connect API key in Config/AppStoreConnect.local."
else
  echo "Signing with the account signed in to Xcode (no Config/AppStoreConnect.local)."
fi
if [[ -n $dry ]]; then
  echo "Dry run: nothing built or sent."
  exit 0
fi

rm -rf "$out"
mkdir -p "$out"
if [[ -n $unsigned ]]; then
  xcodebuild -project Pitchside.xcodeproj -scheme Pitchside -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$out/Pitchside.xcarchive" \
    -derivedDataPath "$out/dd" CODE_SIGNING_ALLOWED=NO -quiet archive
  plutil -p "$out/Pitchside.xcarchive/Products/Applications/Pitchside.app/Info.plist" |
    grep -E 'CFBundle(ShortVersionString|Version|Identifier)"'
  echo "Archived, unsigned. Nothing was sent."
  exit 0
fi
if [[ -n $external ]]; then
  # Apple: builds uploaded as internal only "can only be added to internal tester
  # groups", so a build for outside testers and the App Store leaves the key out.
  cp "$options" "$out/ExportOptions-external.plist"
  options=$out/ExportOptions-external.plist
  /usr/libexec/PlistBuddy -c "Delete :testFlightInternalTestingOnly" "$options"
fi
xcodebuild -project Pitchside.xcodeproj -scheme Pitchside -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$out/Pitchside.xcarchive" \
  -derivedDataPath "$out/dd" -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} -quiet archive
xcodebuild -exportArchive -archivePath "$out/Pitchside.xcarchive" \
  -exportOptionsPlist "$options" -exportPath "$out/export" \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}
echo "Uploaded. App Store Connect takes a few minutes to process it; then it is in TestFlight."
