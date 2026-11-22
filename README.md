# Vitals

Vitals is a system monitor for the macOS menu bar, written in SwiftUI. Each stat gets its own menu bar item, so you can show only the ones you care about and put them where you like. Clicking an item opens a small panel with more detail.

## Items

- **Battery**: charge, health, charge history and the apps using the most energy. The Energy Mode picker lives here too (see below).
- **CPU**: total load, per-core load and the top processes.
- **GPU**: load over the last 10 minutes and the apps using it.
- **Memory**: usage and the top apps.
- **Temps**: temperature sensors and fan speeds.
- **Network**: current speed, the last 10 minutes and connection details.
- **Disk**: storage and read/write activity.
- **Power**: system power draw.

Battery, CPU and Memory are on by default. Turn the rest on, and reorder them, in Settings.

## Requirements

- macOS 27 on Apple Silicon. Intel Macs aren't supported.
- Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and isn't checked in.

## Build and run

```sh
scripts/run.sh            # build Debug and launch it from the build folder
scripts/run.sh --build    # build only
scripts/run.sh --install  # build Release, copy it to /Applications and launch it
scripts/test.sh           # run the unit tests
scripts/test.sh HelperIdentityTests   # run one suite
```

Build products go in `build/`.

## Signing with your own team

The app and its helper have to be signed by a real Apple developer team, because the helper checks the app's signature (and the other way round). `Config/Signing.xcconfig` only holds placeholders, so do this once before the first build:

1. Create `Config/Signing.local.xcconfig`. It's gitignored and overrides the committed file.
2. Put your Team ID and a reverse-DNS prefix you own in it:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   VITALS_BUNDLE_PREFIX = com.yourname
   ```

3. Build as usual. You need an "Apple Development" certificate for that team in your keychain. Without the local file the build stops at code signing.

The bundle IDs, the helper's launchd plist and the signature checks all follow from those two values, so there's nothing else to edit.

## Energy Mode and the helper

The Battery panel can switch the Mac between Low Power, Automatic and High Power, separately for battery and power adapter. Changing that needs root, so Vitals ships a small privileged helper (`VitalsHelper`) that it registers with `SMAppService`. The helper accepts exactly one request, takes plain integers that it checks again, and only runs `/usr/bin/pmset`. It only talks to a copy of Vitals signed by the same team.

The first time you pick a mode, macOS asks you to approve Vitals in System Settings > General > Login Items & Extensions. That's a one-time step. Everything else works without the helper.

## Not App Store material

To show which app is behind a helper process, Vitals calls `responsibility_get_pid_responsible_for_pid`, a private macOS API. It also reads the SMC directly and installs a root helper. None of that would get through App Store review, and a future macOS could break the private call. If the call goes away, Vitals shows the process itself instead of its parent app.

## Credits

The temperature and fan code is adapted from [Stats](https://github.com/exelban/stats) by Serhiy Mytrovtsiy, under the MIT License. Details are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Licence

MIT. See [LICENSE](LICENSE).
