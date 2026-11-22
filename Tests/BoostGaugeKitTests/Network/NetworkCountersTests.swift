import Foundation
import Testing
@testable import BoostGaugeKit

struct NetworkCountersTests {
    @Test func ratesSumInterfaces() {
        let prev = ["en0": IfCounters(ibytes: 1_000, obytes: 500), "en7": IfCounters(ibytes: 0, obytes: 0)]
        let cur = ["en0": IfCounters(ibytes: 5_000, obytes: 1_500), "en7": IfCounters(ibytes: 2_000, obytes: 1_000)]
        let r = NetworkCounters.rates(previous: prev, current: cur, elapsed: 2)
        #expect(r.down == 3_000)
        #expect(r.up == 1_000)
    }

    @Test func counterResetGivesZeroNotHuge() {
        let prev = ["en0": IfCounters(ibytes: 9_000_000, obytes: 9_000_000), "en1": IfCounters(ibytes: 100, obytes: 100)]
        let cur = ["en0": IfCounters(ibytes: 10, obytes: 20), "en1": IfCounters(ibytes: 300, obytes: 500)]
        let r = NetworkCounters.rates(previous: prev, current: cur, elapsed: 1)
        #expect(r.down == 200)
        #expect(r.up == 400)
    }

    @Test func newInterfaceIgnoredFirstTick() {
        let prev = ["en0": IfCounters(ibytes: 100, obytes: 100)]
        let cur = ["en0": IfCounters(ibytes: 200, obytes: 100), "en5": IfCounters(ibytes: 5_000_000_000, obytes: 1)]
        let r = NetworkCounters.rates(previous: prev, current: cur, elapsed: 1)
        #expect(r.down == 100)
        #expect(r.up == 0)
    }

    @Test func loopbackExcluded() {
        let prev = ["lo0": IfCounters(ibytes: 0, obytes: 0), "en0": IfCounters(ibytes: 0, obytes: 0)]
        let cur = ["lo0": IfCounters(ibytes: 1_000_000, obytes: 1_000_000), "en0": IfCounters(ibytes: 10, obytes: 10)]
        let r = NetworkCounters.rates(previous: prev, current: cur, elapsed: 1)
        #expect(r.down == 10)
        #expect(r.up == 10)
    }

    /// Tunnels, bridges and peer-to-peer Wi-Fi carry traffic that also crosses en*, so counting them would double it.
    @Test func virtualInterfacesExcluded() {
        let names = ["utun3", "bridge100", "vmenet0", "awdl0", "llw0", "ipsec0", "gif0", "stf0", "anpi0", "ap1", "nan0"]
        let prev = Dictionary(uniqueKeysWithValues: names.map { ($0, IfCounters(ibytes: 0, obytes: 0)) })
        let cur = Dictionary(uniqueKeysWithValues: names.map { ($0, IfCounters(ibytes: 1_000, obytes: 1_000)) })
        let r = NetworkCounters.rates(previous: prev, current: cur, elapsed: 1)
        #expect(r.down == 0)
        #expect(r.up == 0)
    }

    @Test func zeroElapsedIsZero() {
        let prev = ["en0": IfCounters(ibytes: 0, obytes: 0)]
        let cur = ["en0": IfCounters(ibytes: 10, obytes: 10)]
        let r = NetworkCounters.rates(previous: prev, current: cur, elapsed: 0)
        #expect(r.down == 0 && r.up == 0)
    }

    @Test func compactTable() {
        let table: [(Double, String)] = [
            (0, "0K"), (12_400, "12K"), (1_240_000, "1.2M"), (120_000_000, "120M"), (1_500_000_000, "1.5G"),
            (999_700, "1.0M"), (9_960_000, "10M"), (999_400_000, "999M"),
        ]
        for (value, text) in table {
            #expect(NetworkCounters.compact(value) == text, "\(value)")
        }
    }

    @Test func compactBits() {
        #expect(NetworkCounters.compact(12_000, unit: .bits) == "96Kb")
        #expect(NetworkCounters.compact(1_200_000, unit: .bits) == "9.6Mb")
        #expect(NetworkCounters.compact(0, unit: .bits) == "0Kb")
    }

    @Test func rateText() {
        #expect(NetworkCounters.rateText(12_400, unit: .bytes) == "12 KB/s")
        #expect(NetworkCounters.rateText(1_240_000, unit: .bytes) == "1.2 MB/s")
        #expect(NetworkCounters.rateText(1_200_000, unit: .bits) == "9.6 Mb/s")
    }

    @Test func liveSnapshotHasLoopback() {
        let snap = NetworkCounters.snapshot()
        #expect(snap["lo0"] != nil)
        #expect(snap.keys.contains { $0.hasPrefix("en") })
    }
}
