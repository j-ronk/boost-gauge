import Testing
@testable import BoostGaugeKit

struct FormatTests {
    @Test func percent() {
        #expect(Format.percent(34.4) == "34%")
        #expect(Format.percent(99.6) == "100%")
        #expect(Format.percent(0) == "0%")
        #expect(Format.percent(.nan) == "—")
        #expect(Format.percent(1e300) == "—")
    }

    @Test func watts() {
        #expect(Format.watts(88.24) == "88.2 W")
        #expect(Format.watts(0) == "0.0 W")
        #expect(Format.watts(-0.001) == "0.0 W")
        #expect(Format.watts(.nan) == "—")
    }

    @Test func signedWatts() {
        #expect(Format.signedWatts(16) == "+16.0 W")
        #expect(Format.signedWatts(-16) == "\u{2212}16.0 W")
        #expect(Format.signedWatts(0) == "0.0 W")
        // Rounds to zero, so no sign: "−0.0 W" would read as draining.
        #expect(Format.signedWatts(-0.04) == "0.0 W")
        #expect(Format.signedWatts(.infinity) == "—")
    }

    @Test func hm() {
        #expect(Format.hm(minutes: 42) == "0:42")
        #expect(Format.hm(minutes: 190) == "3:10")
        #expect(Format.hm(minutes: 0) == "0:00")
    }
}
