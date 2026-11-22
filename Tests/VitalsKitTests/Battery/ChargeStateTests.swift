import Foundation
import Testing
@testable import VitalsKit

struct ChargeStateTests {
    @Test func drainingOnACBeatsIsCharging() {
        let s = BatteryFixtures.snapshot("draining-on-ac")
        #expect(ChargeState.classify(s) == .drainingOnAC)
        #expect(ChargeState.classify(s).headerText == "Plugged In · Draining")
    }

    @Test func invalidTimesHidden() {
        #expect(ChargeState.classify(BatteryFixtures.snapshot("charging-no-estimate-synth")).headerText == "Charging")
        #expect(ChargeState.classify(BatteryFixtures.snapshot("on-battery-calculating-synth")).headerText == "On Battery")
    }

    @Test func headerTexts() {
        #expect(ChargeState.charging(42).headerText == "Charging · 0:42 to full")
        #expect(ChargeState.charging(nil).headerText == "Charging")
        #expect(ChargeState.onBattery(190).headerText == "On Battery · 3:10 left")
        #expect(ChargeState.onBattery(nil).headerText == "On Battery")
        #expect(ChargeState.charged.headerText == "Charged")
        #expect(ChargeState.drainingOnAC.headerText == "Plugged In · Draining")
        #expect(ChargeState.onHold.headerText == "Charging On Hold")
        #expect(ChargeState.notCharging.headerText == "Not Charging")
    }

    @Test func recordedCharging() {
        let s = BatteryFixtures.snapshot("charging")
        #expect(ChargeState.classify(s) == .charging(136))
        #expect(ChargeState.classify(s).headerText == "Charging · 2:16 to full")
        #expect(s.batteryW > 50)
    }

    @Test func fixtureStates() {
        #expect(ChargeState.classify(BatteryFixtures.snapshot("charging-synth")) == .charging(42))
        #expect(ChargeState.classify(BatteryFixtures.snapshot("on-battery-synth")) == .onBattery(190))
        #expect(ChargeState.classify(BatteryFixtures.snapshot("charged-synth")) == .charged)
    }

    @Test func onHold() {
        #expect(ChargeState.classify(BatteryFixtures.snapshot("on-hold-optimized-synth")) == .onHold)
        #expect(ChargeState.classify(BatteryFixtures.snapshot("on-hold-limit-synth")) == .onHold)
        var inhibited = BatteryFixtures.snapshot("not-charging-synth")
        inhibited.chargerInhibitReason = 1
        #expect(ChargeState.classify(inhibited) == .onHold)
    }

    @Test func notCharging() {
        // A stop reason well below any charge limit is a fault or thermal stop, not a hold.
        #expect(ChargeState.classify(BatteryFixtures.snapshot("not-charging-synth")) == .notCharging)
        var noReason = BatteryFixtures.snapshot("on-hold-limit-synth")
        noReason.notChargingReason = 0
        #expect(ChargeState.classify(noReason) == .notCharging)
    }

    @Test func onBatteryIgnoresIsCharging() {
        var s = BatteryFixtures.snapshot("on-battery-synth")
        s.isCharging = true
        #expect(ChargeState.classify(s) == .onBattery(190))
    }
}
