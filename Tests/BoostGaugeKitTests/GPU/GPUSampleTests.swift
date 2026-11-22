import Foundation
import Testing
@testable import BoostGaugeKit

/// The `--render` GPU sample feeds the README, so it should look like real use: mostly idle, with bursts.
@MainActor
struct GPUSampleTests {
    private let end = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sameRenderEveryRun() {
        #expect(GPUItem.sampleHistory(end: end).points.map(\.value) == GPUItem.sampleHistory(end: end).points.map(\.value))
    }

    @Test func tenMinutesEndingAtTheHeaderValue() {
        let p = GPUItem.sampleHistory(end: end).points
        #expect(p.last?.date == end)
        #expect(p.last?.value == 100)
        #expect(end.timeIntervalSince(p.first!.date) >= 590)
        #expect(p.allSatisfy { (0...100).contains($0.value) })
    }

    @Test func mostlyLowWithSpikes() {
        let v = GPUItem.sampleHistory(end: end).points.map(\.value).sorted()
        #expect(v[v.count / 2] < 15, "median is idle")
        #expect(v.filter { $0 > 40 }.count >= 10, "bursts")
    }
}
