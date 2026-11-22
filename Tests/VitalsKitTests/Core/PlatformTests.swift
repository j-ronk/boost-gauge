import Foundation
import Testing
@testable import VitalsKit

/// Thin wrappers over IOKit, Process and IOPS, checked against this Mac.
struct PlatformTests {
    @Test func ioRegistryFindsPlatformExpert() {
        let props = IORegistry.properties(ofClass: "IOPlatformExpertDevice")
        #expect(props?["model"] != nil)
        #expect(IORegistry.allProperties(ofClass: "IOPlatformExpertDevice").count >= 1)
    }

    @Test func ioRegistryMissingClass() {
        #expect(IORegistry.properties(ofClass: "VitalsNoSuchClass") == nil)
        #expect(IORegistry.allProperties(ofClass: "VitalsNoSuchClass").isEmpty)
    }

    @Test func shellRunsTool() async {
        let r = await Shell.run("/bin/echo", ["hi"])
        #expect(r.status == 0)
        #expect(r.out == "hi\n")
    }

    @Test func shellReportsExitStatus() async {
        let r = await Shell.run("/usr/bin/false", [])
        #expect(r.status == 1)
    }

    @Test func shellMissingToolFails() async {
        let r = await Shell.run("/nonexistent/tool", [])
        #expect(r.status == -1)
        #expect(r.out.isEmpty)
    }
}

@MainActor
struct PowerSourceMonitorTests {
    @Test func readsLiveSource() {
        let monitor = PowerSourceMonitor()
        #expect([PowerSource.battery, .adapter].contains(monitor.current))
    }

    @Test func testSeamSwitchesSource() {
        let monitor = PowerSourceMonitor(initial: .adapter)
        #expect(monitor.current == .adapter)
        monitor.simulate(.battery)
        #expect(monitor.current == .battery)
    }
}

struct EnergyModeTypesTests {
    @Test func pmsetValues() {
        #expect(EnergyMode.automatic.rawValue == 0)
        #expect(EnergyMode.low.rawValue == 1)
        #expect(EnergyMode.high.rawValue == 2)
        #expect(PowerSource.battery.rawValue == 0)
        #expect(PowerSource.adapter.rawValue == 1)
    }

    @Test func pickerOrderAndTitles() {
        #expect(EnergyMode.pickerOrder == [.low, .automatic, .high])
        #expect(EnergyMode.pickerOrder.map(\.title) == ["Low Power", "Automatic", "High Power"])
    }
}

@MainActor
struct AppContextTests {
    @Test func startsWithoutOptionalFeatures() {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .battery))
        #expect(ctx.energyMode == nil)
        #expect(ctx.onLaunch == nil)
        #expect(ctx.onReopen == nil)
        #expect(ctx.scheduler.items.isEmpty)
        #expect(ctx.powerSource.current == .battery)
    }
}
