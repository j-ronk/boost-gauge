import Foundation
import Testing
@testable import BoostGaugeKit

struct PowerRowsTests {
    @Test func adapterRowOnlyOnAC() {
        let onBattery = PowerRows.rows(BatteryFixtures.snapshot("on-battery-synth"))
        #expect(!onBattery.map(\.label).contains("Adapter"))

        var onAC = BatteryFixtures.snapshot("draining-on-ac")
        onAC.adapterInW = 88.24
        onAC.adapterRatedW = 94
        let rows = PowerRows.rows(onAC)
        #expect(rows.first { $0.label == "Adapter" }?.value == "88.2 W of 94 W")
    }

    @Test func systemAndBattery() {
        let rows = PowerRows.rows(BatteryFixtures.snapshot("draining-on-ac"))
        #expect(rows.map(\.label) == ["System", "Battery", "Adapter"])
        #expect(rows[0].value == "114.4 W")
        #expect(rows[1].value.hasPrefix("\u{2212}"))
    }

    @Test func nilRowsHidden() {
        var s = BatteryFixtures.snapshot("on-battery-synth")
        s.systemLoadW = nil
        #expect(PowerRows.rows(s).map(\.label) == ["Battery"])
    }

    @Test func ratedOnlyAdapter() {
        var s = BatteryFixtures.snapshot("draining-on-ac")
        s.adapterInW = nil
        #expect(PowerRows.rows(s).first { $0.label == "Adapter" }?.value == "94 W")
    }

    @Test func menuBarValue() {
        var s = BatterySnapshot()
        s.systemLoadW = 101.6
        #expect(PowerRows.menuBarValue(s) == "102W")
        s.systemLoadW = nil
        #expect(PowerRows.menuBarValue(s) == "—")
        #expect(PowerRows.menuBarValue(nil) == "—")
    }
}

struct TemperatureFormatTests {
    @Test func units() {
        #expect(BatteryFormat.temperature(32.5, .celsius) == "32.5 °C")
        #expect(BatteryFormat.temperature(32.5, .fahrenheit) == "90.5 °F")
        #expect(BatteryFormat.temperature(nil, .celsius) == "—")
    }
}

@MainActor
struct FanRowsTests {
    private func ctx() -> AppContext {
        AppContext(settings: AppSettings(defaults: TestDefaults().defaults), powerSource: PowerSourceMonitor(initial: .adapter))
    }

    @Test func fanRowsFormatLikeTemps() {
        let rows = PowerRows.fanRows([FanReading(index: 0, rpm: 3454, min: nil, max: nil),
                                      FanReading(index: 1, rpm: 0, min: nil, max: nil)])
        #expect(rows.map(\.label) == ["Fan 1", "Fan 2"])
        #expect(rows[0].value == SensorSummary.rpm(3454))
        #expect(rows[1].value == "Off")
    }

    @Test func noFansNoRows() {
        #expect(PowerRows.fanRows([]).isEmpty)
    }

    @Test func batteryReadsFansOnlyWhileOpen() {
        var reads = 0
        let item = BatteryItem(ctx(), historyURL: TempHistory().url, recordsHistory: false,
                               readFans: { reads += 1; return [FanReading(index: 0, rpm: 2000, min: nil, max: nil)] })
        item.tick(now: .now)
        #expect(reads == 0)
        item.panelDidOpen()
        #expect(reads == 1)
        #expect(item.model.fans.count == 1)
        item.tick(now: .now)
        #expect(reads == 2)
        item.panelDidClose()
        item.tick(now: .now)
        #expect(reads == 2)
        #expect(item.model.fans.isEmpty)
    }

    @Test func powerReadsFansOnlyWhileOpen() {
        var reads = 0
        let item = PowerItem(ctx(), readFans: { reads += 1; return [] })
        item.tick(now: .now)
        #expect(reads == 0)
        item.panelDidOpen()
        item.tick(now: .now)
        #expect(reads == 2)
        item.panelDidClose()
        item.tick(now: .now)
        #expect(reads == 2)
    }
}

@MainActor
struct PowerRecordingTests {
    @Test func recordsSystemAndBatteryMagnitude() {
        let h = ChartHistory()
        let s = BatteryFixtures.snapshot("draining-on-ac")
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        h.recordPower(s, at: t0)
        #expect(h(.powerSystem).points(.tenMinutes, now: t0).map { Double($0.avg) } == [s.systemLoadW.map { Double(Float($0)) }!])
        #expect(h(.powerBattery).points(.tenMinutes, now: t0).map(\.avg) == [Float(abs(s.batteryW))])
        var none = s
        none.systemLoadW = nil
        h.recordPower(none, at: t0.addingTimeInterval(10))
        #expect(h(.powerSystem).points(.tenMinutes, now: t0.addingTimeInterval(10)).count == 1)
        #expect(h(.powerBattery).points(.tenMinutes, now: t0.addingTimeInterval(10)).count == 1)
    }
}
