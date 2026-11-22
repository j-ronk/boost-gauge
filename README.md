# Boost Gauge

A SwiftUI menu bar system monitor for macOS 27 on Apple Silicon. Each stat (battery, CPU, GPU, memory, temps, network, disk, power) is its own menu bar item that you can show, hide and reorder. Click one to open a detail panel.

**Download** the signed, notarised app from [Releases](../../releases).

## Build

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

1. Create `Config/Signing.local.xcconfig` (it's gitignored) with your Team ID and a bundle prefix:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   BOOSTGAUGE_BUNDLE_PREFIX = com.yourname
   ```
2. Run `scripts/run.sh --install` to build and install to /Applications, or `scripts/test.sh` to run the tests.

Maintainers: `scripts/release.sh 1.0.0` builds the notarised release zip. It needs a Developer ID Application certificate and a `notarytool` keychain profile (`xcrun notarytool store-credentials boostgauge-notary`).

## Energy Mode

The Battery panel switches Energy Mode through a small root helper that only runs `pmset` and only talks to Boost Gauge signed by the same team. macOS asks you to allow it once in Login Items.

Boost Gauge uses a private API and reads the SMC directly, so it won't go on the App Store.

## Credits

Temperature and fan code adapted from [Stats](https://github.com/exelban/stats) (MIT). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

MIT licence.
