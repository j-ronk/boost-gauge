# Building Boost Gauge

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

1. Create `Config/Signing.local.xcconfig` (it's gitignored) with your Team ID and a bundle prefix:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   BOOSTGAUGE_BUNDLE_PREFIX = com.yourname
   ```
2. Run `scripts/run.sh --install` to build and install to /Applications, or `scripts/test.sh` to run the tests.

## Releasing

`scripts/release.sh 1.1.0 --publish` builds the notarised DMG and publishes the GitHub release. Leave off `--publish` to only build the DMG.

It needs a Developer ID Application certificate and a `notarytool` keychain profile (`xcrun notarytool store-credentials boostgauge-notary`).
