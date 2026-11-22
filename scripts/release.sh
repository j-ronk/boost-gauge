#!/bin/bash
# Usage: scripts/release.sh <version> [--publish]      e.g. scripts/release.sh 1.1.0 --publish
# Builds a Developer ID-signed, notarised, stapled build/release/BoostGauge-<version>.dmg. Without --publish
# it prints the gh release command; with it, it pushes the current branch and creates the GitHub release. Needs a "Developer ID Application" certificate for the team in
# Config/Signing.local.xcconfig and a notarytool keychain profile (default boostgauge-notary, or set
# BOOSTGAUGE_NOTARY_PROFILE), created once with `xcrun notarytool store-credentials boostgauge-notary`.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$(pwd)

fail() { echo "release: $*" >&2; exit 1; }

usage() { echo "usage: scripts/release.sh <version> [--publish]" >&2; exit 2; }
version="" publish=0
for arg in "$@"; do
  case "$arg" in
    --publish) publish=1 ;;
    -*) usage ;;
    *) [ -z "$version" ] || usage; version=$arg ;;
  esac
done
[ -n "$version" ] || usage
printf '%s' "$version" | grep -Eqx '[0-9]+\.[0-9]+(\.[0-9]+)?' || fail "version must look like 1.0.0, got '$version'"

profile=${BOOSTGAUGE_NOTARY_PROFILE:-boostgauge-notary}
local_config=Config/Signing.local.xcconfig

# --- Early checks: each stops with one line before anything slow runs.
command -v xcodegen >/dev/null || fail "xcodegen not found (brew install xcodegen)"
[ -f "$local_config" ] || fail "$local_config is missing; create it with DEVELOPMENT_TEAM and BOOSTGAUGE_BUNDLE_PREFIX (see README)"
team=$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]{10})[[:space:]]*$/\1/p' "$local_config" | tail -n 1)
[ -n "$team" ] || fail "no 10-character DEVELOPMENT_TEAM in $local_config"
identity=$(security find-identity -v -p codesigning \
  | sed -nE 's/^[[:space:]]*[0-9]+\) [0-9A-F]{40} "(Developer ID Application: .* \('"$team"'\))"$/\1/p' | head -n 1)
[ -n "$identity" ] || fail "no 'Developer ID Application' identity for team $team in the keychain; create one in Xcode > Settings > Accounts > Manage Certificates"
xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 \
  || fail "notary keychain profile '$profile' not found or not working; run: xcrun notarytool store-credentials $profile"
[ -z "$(git status --porcelain)" ] || fail "git tree is dirty; commit or stash first so the release matches a commit"
if [ $publish -eq 1 ]; then
  command -v gh >/dev/null || fail "gh not found (brew install gh)"
  gh auth status >/dev/null 2>&1 || fail "gh is not logged in; run: gh auth login"
  git symbolic-ref -q HEAD >/dev/null || fail "HEAD is detached; check out the branch to release from"
  if gh release view "v$version" >/dev/null 2>&1; then fail "release v$version already exists on GitHub"; fi
fi

commit=$(git rev-parse HEAD)
build_number=$(git rev-list --count HEAD)
out="$root/build/release"
derived="$out/DerivedData"
app="$derived/Build/Products/Release/BoostGauge.app"
zip="$out/BoostGauge-$version.zip"   # scratch upload for the app notarisation
dmg="$out/BoostGauge-$version.dmg"

rm -rf "$out"
mkdir -p "$out"

# --- Build. Command-line settings override project.yml for every target, including the embedded
# helper and framework. Base entitlements are off because notarisation rejects get-task-allow.
echo "Building Boost Gauge $version ($build_number)..."
xcodegen generate --quiet
xcodebuild build \
  -scheme BoostGauge \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived" \
  -quiet \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$identity" \
  DEVELOPMENT_TEAM="$team" \
  OTHER_CODE_SIGN_FLAGS=--timestamp \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_HARDENED_RUNTIME=YES \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_number"
[ -d "$app" ] || fail "build finished but $app is missing"

# --- Verify the signature before spending time on notarisation.
shown=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[ "$shown" = "$version" ] || fail "built app says version $shown, expected $version"
if ! verify=$(codesign --verify --deep --strict --verbose=2 "$app" 2>&1); then
  echo "$verify" >&2
  fail "codesign --verify --deep --strict failed"
fi
echo "$verify" | sed 's/^/  /'

check_signed() {
  local info
  info=$(codesign -dvv "$1" 2>&1) || fail "codesign could not read $1"
  grep -q '^Authority=Developer ID Application: ' <<<"$info" || fail "$1 is not signed with Developer ID Application"
  grep -qx "TeamIdentifier=$team" <<<"$info" || fail "$1 is not signed by team $team"
  grep -q '^Timestamp=' <<<"$info" || fail "$1 has no secure timestamp"
  grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]*\(.*runtime' <<<"$info" || fail "$1 is missing the hardened runtime"
  local ents
  ents=$(codesign -d --entitlements - --xml "$1" 2>/dev/null || true)
  if grep -q 'get-task-allow' <<<"$ents"; then
    fail "$1 has the get-task-allow entitlement, which notarisation rejects"
  fi
  echo "  signed ok: ${1#"$derived/Build/Products/Release/"}"
}
check_signed "$app"
check_signed "$app/Contents/MacOS/BoostGaugeHelper"
check_signed "$app/Contents/Frameworks/BoostGaugeKit.framework"

# --- Notarise and staple. The app is notarised and stapled on its own first so it still passes
# Gatekeeper offline after being dragged out of the DMG; the DMG then gets its own submission.
notarise() {
  local file=$1 json="$out/notary-submit.json" st id state
  set +e
  xcrun notarytool submit "$file" --keychain-profile "$profile" --wait --timeout 30m --output-format json > "$json"
  st=$?
  set -e
  read -r id state < <(/usr/bin/python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
print(d.get("id", "-"), d.get("status", "unknown"))
' "$json")
  if [ "$state" != "Accepted" ]; then
    echo "Notarisation ended as '$state' (notarytool exit $st, submission $id)." >&2
    cat "$json" >&2
    if [ "$id" != "-" ]; then xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || true; fi
    fail "notarisation failed"
  fi
  echo "  notarised ${file##*/}: submission $id (check later with: xcrun notarytool info $id --keychain-profile $profile)"
}
# The ticket can take a minute or two to reach Apple's CDN after Accepted, so retry before failing.
staple() {
  local i=0
  until xcrun stapler staple "$1" >/dev/null 2>&1 || [ $i -ge 8 ]; do sleep 15; i=$((i + 1)); done
  xcrun stapler staple "$1"
  xcrun stapler validate "$1"
}

ditto -c -k --keepParent "$app" "$zip"
echo "Submitting the app to the notary service (can take several minutes)..."
notarise "$zip"
staple "$app"
rm -f "$zip"

# --- Build the DMG: the app plus an Applications shortcut. No Finder layout script, so no
# automation permission prompts.
echo "Building the DMG..."
stage="$out/dmg-stage"
mkdir -p "$stage"
ditto "$app" "$stage/BoostGauge.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Boost Gauge" -srcfolder "$stage" -fs HFS+ -format UDZO -ov -quiet "$dmg"
rm -rf "$stage"
codesign --force --timestamp --sign "$identity" "$dmg"
echo "Submitting the DMG to the notary service..."
notarise "$dmg"
staple "$dmg"

# Check what ships: assess the DMG itself, then the app copy inside it.
assessment=$(spctl -a -vv -t open --context context:primary-signature "$dmg" 2>&1) || { echo "$assessment" >&2; fail "spctl rejected the DMG"; }
echo "$assessment" | sed 's/^/  /'
grep -q 'source=Notarized Developer ID' <<<"$assessment" || fail "spctl accepted the DMG but not as Notarized Developer ID"
mnt="$out/mnt"
mkdir -p "$mnt"
hdiutil attach -nobrowse -readonly -quiet -mountpoint "$mnt" "$dmg" || fail "could not mount the DMG"
detach() { hdiutil detach -quiet "$mnt" || hdiutil detach -force -quiet "$mnt"; }
[ -L "$mnt/Applications" ] && [ "$(readlink "$mnt/Applications")" = "/Applications" ] || { detach; fail "DMG has no Applications link"; }
xcrun stapler validate "$mnt/BoostGauge.app" || { detach; fail "app inside the DMG is not stapled"; }
assessment=$(spctl -a -vv -t exec "$mnt/BoostGauge.app" 2>&1) || { echo "$assessment" >&2; detach; fail "spctl rejected the app in the DMG"; }
detach
echo "$assessment" | sed 's/^/  /'
grep -q 'source=Notarized Developer ID' <<<"$assessment" || fail "spctl accepted the app but not as Notarized Developer ID"
rmdir "$mnt"

# --- Hand over, or publish when asked to with --publish.
sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
notes="Needs macOS 27 on Apple Silicon. Open the DMG and drag Boost Gauge to Applications. The first time you switch Energy Mode, allow the Boost Gauge helper once in System Settings > General > Login Items. SHA-256: $sha"
echo
echo "Built $dmg"
echo "SHA-256: $sha"
echo
if [ $publish -eq 1 ]; then
  echo "Publishing v$version..."
  git push origin HEAD
  gh release create "v$version" "$dmg" --target "$commit" --title "Boost Gauge $version" --notes "$notes"
  git fetch -q --tags origin
  exit 0
fi
echo "To publish, rerun with --publish, or push $commit and run:"
# Plain single quotes are safe: version is digits and dots, and the notes contain no single quote.
echo "gh release create v$version build/release/BoostGauge-$version.dmg --target $commit --title 'Boost Gauge $version' --notes '$notes'"
