import Foundation
import Testing
@testable import BoostGaugeKit

struct BatteryParserTests {
    @Test func drainingOnAC() {
        let s = BatteryFixtures.snapshot("draining-on-ac")
        #expect(s.onAC)
        #expect(s.isCharging)
        #expect(!s.isCharged)
        #expect(s.percent == 18)
        #expect(s.amperage_mA == -3089)
        #expect(s.voltage_mV == 10847)
        // From the same telemetry snapshot as SystemLoad, so adapter in + battery out adds up to the load.
        #expect(s.batteryW == -26.351)
        #expect(abs((s.adapterInW ?? 0) - s.batteryW - (s.systemLoadW ?? 0)) < 0.001)
        #expect(s.minutesToFull == nil)
        #expect(s.minutesToEmpty == nil)
        #expect(s.systemLoadW == 114.415)
        #expect(s.adapterInW == 88.064)
        #expect(s.adapterRatedW == 94)
        #expect(s.cycleCount == 197)
        #expect(s.designCapacity == 8694)
        #expect(s.nominalCapacity == 7757)
        #expect(s.rawMaxCapacity == 7513)
        #expect(s.notChargingReason == 0)
        #expect(s.chargerInhibitReason == 0)
        #expect(!s.optimizedChargingEngaged)
    }

    @Test func temperatureFromPack() {
        var pack = BatteryFixtures.pack
        var data = pack["BatteryData"] as! [String: Any]
        data["Temperature"] = 3250
        pack["BatteryData"] = data
        let s = BatteryParser.parse(iops: BatteryFixtures.iops("draining-on-ac"),
                                    smartBattery: BatteryFixtures.smartBattery("draining-on-ac"), pack: pack)
        #expect(s.temperatureC == 32.5)
        #expect(BatteryFixtures.snapshot("draining-on-ac").temperatureC == nil)
        #expect(BatteryFixtures.snapshot("draining-on-ac", withPack: true).temperatureC == 33.09)
    }

    @Test func onBatteryHasNoAdapter() {
        let s = BatteryFixtures.snapshot("on-battery-synth")
        #expect(!s.onAC)
        #expect(s.minutesToEmpty == 190)
        #expect(s.adapterRatedW == nil)
        #expect(s.adapterInW == nil)
    }

    @Test func invalidTimesAreNil() {
        #expect(BatteryFixtures.snapshot("charging-no-estimate-synth").minutesToFull == nil)
        #expect(BatteryFixtures.snapshot("on-battery-calculating-synth").minutesToEmpty == nil)
        #expect(BatteryFixtures.snapshot("charging-synth").minutesToFull == 42)
    }

    @Test func optimizedChargingKey() {
        #expect(BatteryFixtures.snapshot("on-hold-optimized-synth").optimizedChargingEngaged)
        #expect(BatteryFixtures.snapshot("on-hold-limit-synth").notChargingReason == 4)
    }

    /// ioreg prints negative amperage as an unsigned 64-bit value; the parser must still read it as negative.
    @Test func unsignedAmperageWraps() {
        var sb = BatteryFixtures.smartBattery("draining-on-ac")
        sb["InstantAmperage"] = NSNumber(value: UInt64(bitPattern: -3103))
        let s = BatteryParser.parse(iops: BatteryFixtures.iops("draining-on-ac"), smartBattery: sb, pack: nil)
        #expect(s.amperage_mA == -3103)
    }

    @Test func emptyInputsDoNotCrash() {
        let s = BatteryParser.parse(iops: [:], smartBattery: [:], pack: nil)
        #expect(s.percent == 0)
        #expect(s.healthPercent == nil)
        #expect(s.systemLoadW == nil)
    }
}

struct HealthTests {
    /// Recorded seconds apart: the nominal/design estimate matched Apple's figure at that moment.
    @Test func matchesSystemProfiler() {
        let expected = BatteryParser.maximumCapacityPercent(systemProfiler: Fixture.string("Battery/system-profiler-power.txt"))
        #expect(expected == 89)
        #expect(BatteryFixtures.snapshot("draining-on-ac").healthPercent == expected)
    }

    @Test func systemProfilerParse() {
        #expect(BatteryParser.maximumCapacityPercent(systemProfiler: "") == nil)
        #expect(BatteryParser.maximumCapacityPercent(systemProfiler: "  Maximum Capacity: 100%\n") == 100)
        #expect(BatteryParser.maximumCapacityPercent(systemProfiler: "Maximum Capacity: n/a") == nil)
    }

    @MainActor @Test func modelPrefersAppleFigure() {
        let model = BatteryModel(history: nil)
        model.snapshot = BatteryFixtures.snapshot("draining-on-ac")
        #expect(model.healthPercent == 89)
        model.systemHealthPercent = 88
        #expect(model.healthPercent == 88)
    }

    @Test func planValues() {
        var s = BatterySnapshot()
        s.designCapacity = 8694
        s.nominalCapacity = 7840
        s.rawMaxCapacity = 7596
        #expect(s.healthPercent == 90)
    }
}
