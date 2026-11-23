import Foundation
import Testing
@testable import BoostGaugeKit

@MainActor
struct NetworkItemTests {
    private func make(_ suite: TestDefaults, counters: @escaping () -> [String: IfCounters]) -> (AppContext, NetworkItem) {
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let item = NetworkItem(ctx, snapshot: counters)
        ctx.scheduler.register(item)
        return (ctx, item)
    }

    @Test func hiddenItemReadsNothing() {
        let suite = TestDefaults()
        var reads = 0
        let (ctx, _) = make(suite) { reads += 1; return [:] }
        ctx.scheduler.fire(now: .now)
        #expect(reads == 0)
    }

    @Test func secondTickGivesRateAndChartPoint() {
        let suite = TestDefaults()
        var bytes: UInt64 = 0
        let (ctx, item) = make(suite) { bytes += 4_000; return ["en0": IfCounters(ibytes: bytes * 3, obytes: bytes)] }
        let t0 = Date(timeIntervalSince1970: 1_000)
        item.tick(now: t0)
        #expect(item.rate == nil)
        #expect(item.labelLines == ("↑ —", "↓ —"))
        item.tick(now: t0.addingTimeInterval(2))
        #expect(item.rate?.up == 2_000)
        #expect(item.rate?.down == 6_000)
        #expect(item.labelLines == ("↑ 2K", "↓ 6K"))
        let now = t0.addingTimeInterval(2)
        #expect(ctx.charts(.networkUp).points(.tenMinutes, now: now).map(\.avg) == [2_000])
        #expect(ctx.charts(.networkDown).points(.tenMinutes, now: now).map(\.avg) == [6_000])
    }

    /// Hidden for a while (or asleep): the first tick back must not average over the whole gap.
    @Test func gapResetsBaseline() {
        let suite = TestDefaults()
        var bytes: UInt64 = 0
        let (_, item) = make(suite) { bytes += 1_000_000; return ["en0": IfCounters(ibytes: bytes, obytes: bytes)] }
        let t0 = Date(timeIntervalSince1970: 1_000)
        item.tick(now: t0)
        item.tick(now: t0.addingTimeInterval(2))
        #expect(item.rate != nil)
        item.tick(now: t0.addingTimeInterval(3_600))
        #expect(item.rate == nil)
        item.tick(now: t0.addingTimeInterval(3_602))
        #expect(item.rate?.down == 500_000)
    }

    @Test func labelHonoursUnit() {
        let suite = TestDefaults()
        var bytes: UInt64 = 0
        let (ctx, item) = make(suite) { bytes += 24_000; return ["en0": IfCounters(ibytes: bytes, obytes: bytes / 10)] }
        let t0 = Date(timeIntervalSince1970: 1_000)
        item.tick(now: t0)
        item.tick(now: t0.addingTimeInterval(2))
        #expect(item.labelWidest == "↓ 999M")
        ctx.settings.networkUnit = .bits
        #expect(item.labelLines == ("↑ 10Kb", "↓ 96Kb"))
        #expect(item.labelWidest == "↓ 999Mb")
    }
}
