import Foundation
import Testing
@testable import BoostGaugeKit

struct SensorSummaryTests {
    private static func fixture() -> [(name: String, celsius: Double)] {
        let json = try? JSONSerialization.jsonObject(with: Fixture.data("Sensors/sensor-names.json"))
        let rows = json as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let name = row["name"] as? String, let value = row["celsius"] as? Double else { return nil }
            return (name, value)
        }
    }

    @Test func groupsFixture() throws {
        let readings = Self.fixture()
        #expect(readings.count > 20)
        let s = SensorSummary.summarize(readings)
        let cpu = try #require(s.cpu), gpu = try #require(s.gpu), battery = try #require(s.battery)
        #expect((20...110).contains(cpu))
        #expect((20...110).contains(gpu))
        #expect((10...60).contains(battery))
        let grouped = readings.filter { SensorSummary.group(of: $0.name) != nil }.map(\.celsius)
        #expect(s.hottest == grouped.max())
        #expect(s.hottest! >= max(cpu, gpu, battery))
        // Power manager die sensors are in the recording but belong to no group.
        #expect(readings.contains { $0.name.hasPrefix("TPD") })
        #expect(SensorSummary.group(of: "TPD0") == nil)
    }

    @Test func groupsByStatsKeyFamilies() {
        let s = SensorSummary.summarize([
            ("Tp01", 80), ("Tp09", 60),        // CPU cores
            ("Tp02", 120),                     // Tp but not in Stats' tables: not shown
            ("Tg05", 50), ("Tg0D", 54),        // GPU
            ("TPD0", 99),                      // power manager die: not shown
            ("TB1T", 30), ("TB2T", 32),        // battery cells
            ("TaLP", 140), ("Tm02", 45),       // airflow, memory: not shown
        ])
        #expect(s == TempSummary(cpu: 70, gpu: 52, battery: 31, hottest: 80, cpuHottest: 80))
    }

    /// M3 files CPU and GPU under the same `Tf` prefix, so grouping must follow Stats' tables, not prefixes.
    @Test func m3Keys() {
        #expect(SensorSummary.group(of: "Te05") == .cpu)
        #expect(SensorSummary.group(of: "Tf04") == .cpu)
        #expect(SensorSummary.group(of: "Tf14") == .gpu)
        #expect(SensorSummary.group(of: "Tg1U") == .gpu)
        #expect(SensorSummary.group(of: "TB0T") == .battery)
        #expect(SensorSummary.group(of: "TBxT") == nil)
        #expect(SensorSummary.group(of: "TB٣T") == nil)
    }

    @Test func dropsBogusValues() {
        let s = SensorSummary.summarize([("Tp01", 0), ("Tp05", -3), ("Tp09", 151), ("Tp0D", 64), ("Tg05", 0)])
        #expect(s.cpu == 64)
        #expect(s.gpu == nil)
        #expect(s.hottest == 64)
    }

    @Test func cpuHottestIsTheHottestCPUSensorOnly() {
        let s = SensorSummary.summarize([("Tp01", 61), ("Tp05", 74.5), ("Tp09", 0), ("Tg05", 88), ("TB1T", 30)])
        #expect(s.cpu == (61 + 74.5) / 2)
        #expect(s.cpuHottest == 74.5)
        #expect(s.hottest == 88)
        #expect(SensorSummary.summarize([("Tg05", 50)]).cpuHottest == nil)
    }

    @Test func emptyGivesNilHottest() {
        #expect(SensorSummary.summarize([]) == TempSummary(cpu: nil, gpu: nil, battery: nil, hottest: nil))
    }

    @Test func formatsUnits() {
        #expect(SensorSummary.format(62.4, .celsius) == "62°C")
        #expect(SensorSummary.format(62.2, .fahrenheit) == "144°F")
        #expect(SensorSummary.format(100, .fahrenheit) == "212°F")
    }

    @Test func formatsRPM() {
        let us = Locale(identifier: "en_US")
        #expect(SensorSummary.rpm(2317.4, locale: us) == "2,317 rpm")
        #expect(SensorSummary.rpm(0, locale: us) == "Off")
        #expect(SensorSummary.rpm(0.4, locale: us) == "Off")
    }
}
