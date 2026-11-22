import Foundation
import Testing
@testable import BoostGaugeKit

struct DiskStatsTests {
    @Test func rates() {
        let r = DiskStats.rates(previous: (read: 1_000, write: 2_000), current: (read: 5_000, write: 2_500), elapsed: 2)
        #expect(r.read == 2_000)
        #expect(r.write == 250)
    }

    /// A disk ejected between samples makes the summed counters go down.
    @Test func ratesNeverNegative() {
        let r = DiskStats.rates(previous: (read: 9_000, write: 9_000), current: (read: 1_000, write: 9_100), elapsed: 1)
        #expect(r.read == 0)
        #expect(r.write == 100)
        let z = DiskStats.rates(previous: (read: 0, write: 0), current: (read: 10, write: 10), elapsed: 0)
        #expect(z.read == 0 && z.write == 0)
    }

    @Test func freeLabelTable() {
        let table: [(Int64, String)] = [
            (412_300_000_000, "412G"), (1_200_000_000_000, "1.2T"), (5_400_000_000, "5.4G"),
            (999_600_000_000, "1.0T"), (12_400_000_000_000, "12T"), (0, "0.0G"),
        ]
        for (bytes, text) in table {
            #expect(DiskStats.freeLabel(bytes) == text, "\(bytes)")
        }
    }

    @Test func parsesBlockStorageFixture() throws {
        let drivers = try #require(Fixture.plist("Disk/blockstorage.plist") as? [[String: Any]])
        let t = DiskStats.totals(drivers)
        #expect(t.read == 50_098_949_632 + 1_169_022_140_416 + 424_459_264)
        #expect(t.write == 113_909_248 + 734_157_840_384)
    }

    @Test func totalsSkipMissingStatistics() {
        let t = DiskStats.totals([["Statistics": ["Bytes (Read)": 10, "Bytes (Write)": 20]], ["Other": 1]])
        #expect(t.read == 10 && t.write == 20)
    }
}
