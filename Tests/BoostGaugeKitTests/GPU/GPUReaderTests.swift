import Foundation
import Testing
@testable import BoostGaugeKit

struct GPUReaderTests {
    @Test func readsUtilization() throws {
        let services = try #require(Fixture.plist("GPU/gpu.plist") as? [[String: Any]])
        #expect(GPUReader.utilization(services) == 99)
    }

    @Test func missingIsNil() throws {
        let services = try #require(Fixture.plist("GPU/gpu-missing.plist") as? [[String: Any]])
        #expect(GPUReader.utilization(services) == nil)
        #expect(GPUReader.utilization([]) == nil)
    }

    @Test func maxAcrossAccelerators() {
        let a: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": 12]]
        let b: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": 40]]
        #expect(GPUReader.utilization([a, [:], b]) == 40)
    }

    @Test func outOfRangeIsClamped() {
        let a: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": 140]]
        #expect(GPUReader.utilization([a]) == 100)
    }

    @Test func readsThisMac() {
        #expect(GPUReader.readAccelerators().contains { $0["PerformanceStatistics"] != nil })
    }
}

@MainActor
struct GPUItemTests {
    @Test func reshowClearsHistory() async throws {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        ctx.settings.setShown(.gpu, true)
        var reads = 0
        let item = GPUItem(ctx, read: { reads += 1; return 30 })
        item.tick(now: .now)
        #expect(item.model.utilization == 30)
        #expect(item.model.history.points.count == 1)
        #expect(item.model.labelValue == "30%")

        ctx.settings.setShown(.gpu, false)
        try await Task.sleep(for: .milliseconds(50))
        // A line drawn across the hidden span would claim readings nobody took.
        #expect(item.model.history.points.isEmpty)
        #expect(item.model.utilization == nil)
        #expect(reads == 1)
    }

    @Test func nilReadingShowsDash() {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let item = GPUItem(ctx, read: { nil })
        item.tick(now: .now)
        #expect(item.model.labelValue == "—")
        #expect(item.model.history.points.isEmpty)
    }

    @Test func historySplitsAtGaps() {
        let t0 = Date(timeIntervalSince1970: 0)
        let points = [(t0, 1.0), (t0 + 2, 2.0), (t0 + 4, 3.0), (t0 + 200, 4.0), (t0 + 202, 5.0)]
            .map { (date: $0.0, value: $0.1) }
        let segments = GPUHistory.segments(points, maxGap: 10)
        #expect(segments.map(\.count) == [3, 2])
    }
}

struct GPUDetailsTests {
    @Test func readsMemoryAndCores() throws {
        let services = try #require(Fixture.plist("GPU/gpu.plist") as? [[String: Any]])
        #expect(GPUReader.memoryInUse(services) == 20_395_376_640)
        #expect(GPUReader.coreCount(services) == 32)
    }

    @Test func missingDetailsAreNil() throws {
        let services = try #require(Fixture.plist("GPU/gpu-missing.plist") as? [[String: Any]])
        #expect(GPUReader.memoryInUse(services) == nil)
        #expect(GPUReader.memoryInUse([]) == nil)
        #expect(GPUReader.coreCount([]) == nil)
        #expect(GPUReader.coreCount([["gpu-core-count": 0]]) == nil)
    }

    @Test func readsThisMacsDetails() {
        let services = GPUReader.readAccelerators(keys: GPUReader.detailKeys)
        #expect(GPUReader.coreCount(services) ?? 0 > 0)
        #expect(GPUReader.memoryInUse(services) != nil)
    }
}
