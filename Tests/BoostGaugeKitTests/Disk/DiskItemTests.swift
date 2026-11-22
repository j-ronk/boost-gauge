import Foundation
import Testing
@testable import BoostGaugeKit

@MainActor
struct DiskItemTests {
    private func make(_ suite: TestDefaults, capacity: @escaping @Sendable () -> DiskCapacity?,
                      totals: @escaping () -> (read: UInt64, write: UInt64)) -> (AppContext, DiskItem) {
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let item = DiskItem(ctx, readCapacity: capacity, readTotals: totals)
        ctx.scheduler.register(item)
        return (ctx, item)
    }

    nonisolated private static let sample = DiskCapacity(name: "Macintosh HD", available: 412_300_000_000, total: 994_662_584_320)

    @Test func hiddenItemReadsNothing() async {
        let suite = TestDefaults()
        let reads = Counter()
        var totalsReads = 0
        let (ctx, item) = make(suite, capacity: { reads.bump(); return Self.sample }, totals: { totalsReads += 1; return (0, 0) })
        ctx.scheduler.fire(now: .now)
        await item.capacityRefresh?.value
        #expect(reads.value == 0)
        #expect(totalsReads == 0)
    }

    /// Finder's "available" figure costs tens of ms, and free space barely moves, so the label re-reads it at most once a minute.
    @Test func capacityReadAtMostOncePerMinute() async {
        let suite = TestDefaults()
        let reads = Counter()
        let (_, item) = make(suite, capacity: { reads.bump(); return Self.sample }, totals: { (0, 0) })
        let t0 = Date(timeIntervalSince1970: 1_000)
        #expect(item.labelValue == "—")
        item.tick(now: t0)
        await item.capacityRefresh?.value
        #expect(item.labelValue == "412G")
        item.tick(now: t0.addingTimeInterval(30))
        await item.capacityRefresh?.value
        #expect(reads.value == 1)
        item.tick(now: t0.addingTimeInterval(61))
        await item.capacityRefresh?.value
        #expect(reads.value == 2)
    }

    @Test func activityNeedsTwoSamplesAndResetsOnClose() {
        let suite = TestDefaults()
        var read: UInt64 = 0
        let (_, item) = make(suite, capacity: { Self.sample }, totals: { read += 4_000_000; return (read, read / 2) })
        let t0 = Date(timeIntervalSince1970: 1_000)
        item.sampleActivity(now: t0)
        #expect(item.activity == nil)
        item.sampleActivity(now: t0.addingTimeInterval(2))
        #expect(item.activity?.read == 2_000_000)
        #expect(item.activity?.write == 1_000_000)
        item.panelDidClose()
        #expect(item.activity == nil)
        item.sampleActivity(now: t0.addingTimeInterval(600))
        #expect(item.activity == nil)
    }
}

/// Capacity reads happen off the main actor, so the count needs a lock.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
