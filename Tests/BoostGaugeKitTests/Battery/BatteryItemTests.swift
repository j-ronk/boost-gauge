import Foundation
import IOKit
import Observation
import Testing
@testable import BoostGaugeKit

@MainActor
struct BatteryItemTests {
    @Test func renderModeNeverWritesHistory() async throws {
        let tmp = TempHistory()
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let item = BatteryItem(ctx, historyURL: tmp.url, recordsHistory: false)
        #expect(item.id == .battery)
        item.tick(now: .now)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!FileManager.default.fileExists(atPath: tmp.url.path))
    }

    /// `--render` ticks items but never opens a panel, so a pack read gated on the panel left Temperature at "—".
    @Test(.enabled(if: BatteryItemTests.packTemperatureExposed))
    func tickReadsTemperatureWithoutAnOpenPanel() {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let item = BatteryItem(ctx, historyURL: TempHistory().url, recordsHistory: false)
        item.tick(now: .now)
        #expect(item.model.snapshot?.temperatureC != nil)
    }

    /// Desktops and CI runners have no battery pack.
    nonisolated static var packTemperatureExposed: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBatteryPack"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        let data = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        return data?["Temperature"] != nil || data?["VirtualTemperature"] != nil
    }

    @Test func recordsHistoryWritesSamples() async throws {
        let tmp = TempHistory()
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let item = BatteryItem(ctx, historyURL: tmp.url, recordsHistory: true)
        var i = 0
        // First launch seeds from pmset (about 1 s) before the first sample lands.
        while !FileManager.default.fileExists(atPath: tmp.url.path), i < 100 {
            try await Task.sleep(for: .milliseconds(100))
            i += 1
        }
        #expect(FileManager.default.fileExists(atPath: tmp.url.path))
        withExtendedLifetime(item) {}
    }

    @Test func renderVariantsCoverEveryState() async {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let item = BatteryItem(ctx, historyURL: TempHistory().url, recordsHistory: false)
        let names = await item.renderVariants().map(\.name)
        #expect(names.starts(with: ["live", "charging-34", "charging-34-1h", "charging-34-24h", "draining-on-ac-31", "charged-100",
                                    "on-battery-8", "on-hold-80", "charging-34-10d"]))
        let states = BatterySamples.all.map { ChargeState.classify($0.snapshot) }
        #expect(states == [.charging(114), .drainingOnAC, .charged, .onBattery(23), .onHold])
    }

    @Test func labelContentOnlyChangesWithIcon() {
        let model = BatteryModel(history: nil)
        var s = BatteryFixtures.snapshot("charging-synth")
        model.snapshot = s
        #expect(model.labelContent == LabelContent(percent: 34, glyph: .bolt))
        final class Counter: @unchecked Sendable { var value = 0 }
        let changes = Counter()
        withObservationTracking { _ = model.labelContent } onChange: { changes.value += 1 }
        s.amperage_mA += 50
        model.snapshot = s
        #expect(changes.value == 0)
        s.percent = 35
        model.snapshot = s
        #expect(changes.value == 1)
    }
}
