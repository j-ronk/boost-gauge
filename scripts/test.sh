#!/bin/bash
# Usage: scripts/test.sh [TestSuite[/test]]
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet

only=()
if [ $# -gt 0 ]; then only+=("-only-testing:BoostGaugeKitTests/$1"); fi

# -quiet hides per-test results, so keep a result bundle and print the counts from it.
mkdir -p build/TestResults
# Keep only the newest few bundles; each is several MB.
{ ls -dt build/TestResults/*.xcresult 2>/dev/null || true; } | tail -n +6 | while read -r old; do /bin/rm -rf "$old"; done
bundle="build/TestResults/$(date +%Y%m%d-%H%M%S)-$$.xcresult"

set +e
xcodebuild test \
  -scheme BoostGaugeKitTests \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "$bundle" \
  -quiet \
  ${only[@]+"${only[@]}"}
status=$?
set -e

if [ -d "$bundle" ]; then
  xcrun xcresulttool get test-results summary --path "$bundle" --compact | /usr/bin/python3 -c '
import json, sys
s = json.load(sys.stdin)
print("%s: %d passed, %d failed, %d skipped" % (s["result"], s["passedTests"], s["failedTests"], s["skippedTests"]))
for f in s.get("testFailures", []):
    print("  FAILED %s: %s" % (f.get("testIdentifierString", f.get("testName")), f.get("failureText", "")))
'
fi
exit $status
