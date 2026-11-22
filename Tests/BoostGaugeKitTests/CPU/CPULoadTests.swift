import Foundation
import Testing
@testable import BoostGaugeKit

struct CPULoadTests {
    @Test func busyFraction() {
        let usage = CPULoad.usage(previous: [CoreTicks(user: 100, system: 50, idle: 850, nice: 0)],
                                  current: [CoreTicks(user: 200, system: 100, idle: 900, nice: 0)])
        #expect(usage.total == 75.0)
        #expect(usage.perCore == [75.0])
    }

    @Test func zeroDeltaIsZero() {
        let t = CoreTicks(user: 5, system: 5, idle: 5, nice: 5)
        let usage = CPULoad.usage(previous: [t, t], current: [t, t])
        #expect(usage.total == 0)
        #expect(usage.perCore == [0, 0])
        #expect(!usage.total.isNaN)
    }

    @Test func totalIsTickWeighted() {
        // Core 0: 10 of 10 ticks busy. Core 1: 0 of 30. A plain mean of cores would say 50%.
        let usage = CPULoad.usage(
            previous: [CoreTicks(user: 0, system: 0, idle: 0, nice: 0), CoreTicks(user: 0, system: 0, idle: 0, nice: 0)],
            current: [CoreTicks(user: 6, system: 3, idle: 0, nice: 1), CoreTicks(user: 0, system: 0, idle: 30, nice: 0)])
        #expect(usage.total == 25.0)
        #expect(usage.perCore == [100.0, 0.0])
    }

    @Test func counterWrapIsHandled() {
        let usage = CPULoad.usage(previous: [CoreTicks(user: UInt32.max - 9, system: 0, idle: UInt32.max - 9, nice: 0)],
                                  current: [CoreTicks(user: 10, system: 0, idle: 10, nice: 0)])
        #expect(usage.total == 50.0)
    }

    @Test func mismatchedCoreCountsGiveNothing() {
        let t = CoreTicks(user: 1, system: 1, idle: 1, nice: 1)
        let usage = CPULoad.usage(previous: [t], current: [t, t])
        #expect(usage.perCore.isEmpty)
        #expect(usage.total == 0)
    }

    @Test func coreKindsM1Max() {
        let kinds = CPULoad.coreKinds(performance: 8, efficiency: 2)
        #expect(kinds == [.efficiency, .efficiency] + Array(repeating: .performance, count: 8))
    }

    @Test func readsThisMac() throws {
        let ticks = try #require(CPUTicks.read())
        #expect(ticks.count == ProcessInfo.processInfo.activeProcessorCount)
    }
}
