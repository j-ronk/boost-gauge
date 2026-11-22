import Foundation
import Testing
@testable import BoostGaugeKit

/// Serves canned per-core ticks and counts how often the item asked.
@MainActor final class TickFeed {
    var reads = 0
    private var step: UInt32 = 0

    /// Each read advances one core by 30 busy + 10 idle ticks: a steady 75%.
    func read() -> [CoreTicks]? {
        reads += 1
        step += 1
        return [CoreTicks(user: 20 * step, system: 10 * step, idle: 10 * step, nice: 0)]
    }
}

@MainActor
struct CPUItemTests {
    private func makeContext(_ suite: TestDefaults) -> AppContext {
        AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
    }

    @Test func hiddenItemReadsNothing() {
        let suite = TestDefaults()
        let ctx = makeContext(suite)
        let feed = TickFeed()
        let item = CPUItem(ctx, readTicks: feed.read)
        ctx.scheduler.register(item)
        ctx.settings.setShown(.cpu, false)
        for _ in 0..<3 { ctx.scheduler.fire(now: .now) }
        #expect(feed.reads == 0)
        #expect(item.model.total == nil)
    }

    @Test func secondTickHasValue() {
        let suite = TestDefaults()
        let ctx = makeContext(suite)
        let feed = TickFeed()
        let item = CPUItem(ctx, readTicks: feed.read)
        item.tick(now: .now)
        #expect(item.model.total == nil)
        item.tick(now: .now)
        #expect(item.model.total == 75)
        #expect(item.model.cores.map(\.percent) == [75])
    }

    @Test func reshowResetsBaseline() async throws {
        let suite = TestDefaults()
        let ctx = makeContext(suite)
        let feed = TickFeed()
        let item = CPUItem(ctx, readTicks: feed.read)
        item.tick(now: .now)
        item.tick(now: .now)
        #expect(item.model.total == 75)

        ctx.settings.setShown(.cpu, false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(item.model.total == nil)
        ctx.settings.setShown(.cpu, true)
        try await Task.sleep(for: .milliseconds(50))

        // A delta across the hidden span would mix stale ticks in; the first tick back only re-baselines.
        item.tick(now: .now)
        #expect(item.model.total == nil)
        item.tick(now: .now)
        #expect(item.model.total == 75)
    }

    @Test func gapResetsBaseline() {
        let suite = TestDefaults()
        let ctx = makeContext(suite)
        let item = CPUItem(ctx, readTicks: TickFeed().read)
        let t0 = Date(timeIntervalSince1970: 0)
        item.tick(now: t0)
        item.tick(now: t0 + 2)
        #expect(item.model.total == 75)
        // Asleep for an hour: no reading spans the gap.
        item.tick(now: t0 + 3600)
        #expect(item.model.total == nil)
        item.tick(now: t0 + 3602)
        #expect(item.model.total == 75)
    }

    @Test func labelShowsDashUntilFirstValue() {
        let suite = TestDefaults()
        let item = CPUItem(makeContext(suite), readTicks: { nil })
        #expect(item.model.labelValue == "—")
        item.model.total = 21.4
        #expect(item.model.labelValue == "21%")
    }

    @Test func detailsShowCPUAverageHottestSensorAndCoreSplit() {
        let suite = TestDefaults()
        let ctx = makeContext(suite)
        let item = CPUItem(ctx, readTicks: { nil }, readTemperatures: {
            SensorSummary.summarize([("Tp01", 60), ("Tp05", 70), ("Tg05", 90)])
        }, kinds: CPULoad.coreKinds(performance: 6, efficiency: 4))
        item.refreshDetails()
        #expect(item.model.temperatureText == "65°C")
        // The GPU sensor is hotter but isn't a CPU sensor.
        #expect(item.model.hottestSensorText == "70°C")
        #expect(item.model.coresText == "4 Efficiency · 6 Performance")

        ctx.settings.temperatureUnit = .fahrenheit
        item.refreshDetails()
        #expect(item.model.temperatureText == "149°F")
    }

    @Test func hiddenDetailsSkipTheSensorRead() {
        let suite = TestDefaults()
        let ctx = makeContext(suite)
        var reads = 0
        let item = CPUItem(ctx, readTicks: { nil }, readTemperatures: { reads += 1; return TempSummary(cpu: 50, cpuHottest: 55) })
        ctx.settings.setSectionShown(.cpuDetails, false)
        item.refreshDetails()
        #expect(reads == 0)
        #expect(item.model.temperatureText == "—")
        ctx.settings.setSectionShown(.cpuDetails, true)
        item.refreshDetails()
        ctx.settings.setSectionShown(.cpuDetails, false)
        item.refreshDetails()
        #expect(item.model.temperatureText == "—", "a hidden section drops its old reading")
        ctx.settings.setSectionShown(.cpuDetails, true)
        item.refreshDetails()
        #expect(reads == 2)
        #expect(item.model.temperatureText == "50°C")
    }

    @Test func hiddenTopProcessesSampleNothing() async {
        let suite = TestDefaults()
        let ctx = makeContext(suite)
        let item = CPUItem(ctx, readTicks: { nil })
        ctx.settings.setSectionShown(.cpuTopProcesses, false)
        item.model.topProcesses = []
        await item.refreshTop()
        #expect(item.model.topProcesses == nil)
    }

    @Test func coresTextWithoutAPerformanceSplit() {
        #expect(CPUCores.text(efficiency: 4, performance: 6) == "4 Efficiency · 6 Performance")
        #expect(CPUCores.text(efficiency: 0, performance: 8) == "8")
        #expect(CPUCores.text(efficiency: 0, performance: 0) == "—")
        // Intel: no perflevel sysctls, so the logical core count stands in.
        #expect(CPUCores.text(efficiency: 0, performance: 0, logical: 8) == "8")
    }
}
