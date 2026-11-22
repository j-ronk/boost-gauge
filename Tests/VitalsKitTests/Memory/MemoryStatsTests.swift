import Foundation
import Testing
@testable import VitalsKit

struct MemoryStatsTests {
    @Test func usedFormula() {
        // (1000 − 100 + 300 + 200) pages × 16 KiB = 1400 × 16384 = 22,937,600 bytes of 45,875,200 total.
        let stats = MemoryStats.from(internal: 1000, purgeable: 100, wired: 300, compressed: 200,
                                     pageSize: 16384, total: 45_875_200)
        #expect(stats.usedBytes == 22_937_600)
        #expect(stats.usedPercent == 50.0)
    }

    @Test func purgeableAboveInternalDoesNotUnderflow() {
        let stats = MemoryStats.from(internal: 10, purgeable: 50, wired: 5, compressed: 0, pageSize: 4096, total: 4096 * 100)
        #expect(stats.usedBytes == 5 * 4096)
    }

    @Test func zeroTotalIsZeroPercent() {
        let stats = MemoryStats.from(internal: 1, purgeable: 0, wired: 0, compressed: 0, pageSize: 4096, total: 0)
        #expect(stats.usedPercent == 0)
    }

    @Test func pressureLevels() {
        #expect(MemoryPressure(sysctlLevel: 1) == .normal)
        #expect(MemoryPressure(sysctlLevel: 2) == .warning)
        #expect(MemoryPressure(sysctlLevel: 4) == .critical)
        #expect(MemoryPressure(sysctlLevel: 0) == .normal)
        #expect(MemoryPressure(sysctlLevel: 3) == .normal)
        #expect(MemoryPressure.critical.rawValue == "Critical")
    }

    @Test func usedText() {
        let gib: UInt64 = 1 << 30
        #expect(MemoryFormat.usedOfTotal(used: UInt64(41.2 * Double(gib)), total: 64 * gib) == "41.2 GB of 64 GB")
        #expect(MemoryFormat.gigabytes(UInt64(2.08 * Double(gib))) == "2.1 GB")
        #expect(MemoryFormat.gigabytes(0) == "0 GB")
        #expect(MemoryFormat.appSize(412 << 20) == "412 MB")
        #expect(MemoryFormat.appSize(3 * gib) == "3.0 GB")
    }

    @Test func topAppsRollUpByApp() {
        let rows = [(key: "/Applications/Chrome.app", bytes: UInt64(300)),
                    (key: "cmd:node", bytes: 500),
                    (key: "/Applications/Chrome.app", bytes: 400),
                    (key: "cmd:zsh", bytes: 10)]
        let top = MemoryTop.rollUp(rows, n: 2)
        #expect(top.map(\.key) == ["/Applications/Chrome.app", "cmd:node"])
        #expect(top.map(\.bytes) == [700, 500])
    }

    @Test func readsThisMac() throws {
        let stats = try #require(MemoryStats.read())
        #expect(stats.usedBytes > 0)
        #expect(stats.usedPercent > 0 && stats.usedPercent <= 100)
        #expect(MemoryStats.swapUsedBytes() != nil)
    }
}
