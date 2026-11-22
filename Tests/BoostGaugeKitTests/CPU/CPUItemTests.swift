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
}
