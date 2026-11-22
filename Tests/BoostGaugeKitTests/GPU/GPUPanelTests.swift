import AppKit
import Foundation
import Testing
@testable import BoostGaugeKit

@MainActor
struct GPUPanelTests {
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        func hit(_ name: String) { lock.withLock { counts[name, default: 0] += 1 } }
        subscript(_ name: String) -> Int { lock.withLock { counts[name, default: 0] } }
    }

    private func makeItem(calls: Calls, readings: [GPUPanelReading], dates: [Date]) -> (GPUItem, AppSettings) {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        ctx.settings.setShown(.gpu, true)
        var nextDate = 0
        let item = GPUItem(
            ctx,
            read: { calls.hit("load"); return 20 },
            readPanel: {
                calls.hit("panel")
                let n = calls["panel"] - 1
                return readings[min(n, readings.count - 1)]
            },
            readTemperature: { calls.hit("temp"); return 48.6 },
            appKey: { ["2486": "Safari", "2481": "Safari"]["\($0)"] ?? "pid\($0)" },
            resolve: { pid in (["176": "WindowServer", "2486": "Safari", "2493": "Herdr"]["\(pid)"] ?? "?", NSImage()) },
            now: { defer { nextDate += 1 }; return dates[min(nextDate, dates.count - 1)] },
            settle: .zero
        )
        return (item, ctx.settings)
    }

    private func reading(_ fixture: String) throws -> GPUPanelReading {
        let clients = try #require(Fixture.plist("GPU/\(fixture).plist") as? [[String: Any]])
        return GPUPanelReading(memoryBytes: 710_721_536, cores: 32, gpuTime: GPUClients.gpuTime(clients))
    }

    @Test func closedPanelReadsOnlyLoad() {
        let calls = Calls()
        let (item, _) = makeItem(calls: calls, readings: [GPUPanelReading()], dates: [.now])
        for i in 0..<5 { item.tick(now: .now.addingTimeInterval(Double(i))) }
        #expect(calls["load"] == 5)
        // Walking the user clients and the SMC only pays off while someone is looking.
        #expect(calls["panel"] == 0)
        #expect(calls["temp"] == 0)
        #expect(item.model.topApps == nil)
    }

    @Test func openPanelFillsDetailsAndTopApps() async throws {
        let calls = Calls()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let (item, _) = makeItem(calls: calls, readings: [try reading("clients-a"), try reading("clients-b")], dates: [t0, t0 + 2])
        await item.refreshPanel()
        #expect(calls["panel"] == 2)
        #expect(calls["temp"] == 1)
        #expect(calls["load"] == 0)
        #expect(item.model.memoryBytes == 710_721_536)
        #expect(item.model.cores == 32)
        #expect(item.model.temperature == 48.6)
        let rows = try #require(item.model.topApps)
        // Crisp's 0.2% rounds to 0% and is left out.
        #expect(rows.map(\.name) == ["WindowServer", "Safari", "Herdr"])
        #expect(rows.map { Format.percent($0.percent) } == ["4%", "2%", "2%"])
    }

    @Test func laterRefreshesReuseTheBaseline() async throws {
        let calls = Calls()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let (item, _) = makeItem(calls: calls, readings: [try reading("clients-a"), try reading("clients-b"), try reading("clients-b")],
                                 dates: [t0, t0 + 2, t0 + 5])
        await item.refreshPanel()
        await item.refreshPanel()
        #expect(calls["panel"] == 3)
        // Nothing drew between the last two readings.
        #expect(item.model.topApps?.isEmpty == true)
    }

    @Test func closingDropsPanelState() async throws {
        let calls = Calls()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let (item, _) = makeItem(calls: calls, readings: [try reading("clients-a"), try reading("clients-b")], dates: [t0, t0 + 2])
        await item.refreshPanel()
        item.panelDidClose()
        #expect(item.model.topApps == nil)
        // The next open measures a fresh interval rather than one spanning the closed time.
        await item.refreshPanel()
        #expect(calls["panel"] == 4)
    }

    @Test func temperatureFollowsUnitSetting() async {
        let calls = Calls()
        let (item, settings) = makeItem(calls: calls, readings: [GPUPanelReading()], dates: [.now])
        settings.temperatureUnit = .fahrenheit
        await item.refreshPanel()
        #expect(item.model.temperatureText == "119°F")
        #expect(item.model.memoryText == "—")
        #expect(item.model.coresText == "—")
    }
}
