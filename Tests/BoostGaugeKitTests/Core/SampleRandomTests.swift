import Testing
@testable import BoostGaugeKit

struct SampleRandomTests {
    @Test func sameSeedSameSequence() {
        var a = SampleRandom(seed: 42), b = SampleRandom(seed: 42), c = SampleRandom(seed: 43)
        let x = (0..<8).map { _ in a.next() }
        #expect(x == (0..<8).map { _ in b.next() })
        #expect(x != (0..<8).map { _ in c.next() })
    }

    @Test func uniformStaysInRange() {
        var r = SampleRandom(seed: 1)
        #expect((0..<1000).allSatisfy { _ in (-2.0...3.0).contains(r.uniform(-2...3)) })
    }
}
