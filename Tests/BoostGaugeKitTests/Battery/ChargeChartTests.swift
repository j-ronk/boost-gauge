import Foundation
import Testing
@testable import BoostGaugeKit

@MainActor
struct ChargeChartTests {
    private func points(_ times: StrideTo<Double>, _ value: Float) -> [ChartPoint] {
        times.map { ChartPoint(t: $0, avg: value, peak: value) }
    }

    @Test func loggedStretchFillsTheRecordedGapAndJoinsIt() {
        // Recorded 0–3000 s and 9000–12000 s, a minute apart; logged every 5 min across the whole time.
        let recorded = points(stride(from: 0, to: 3000, by: 60), 80) + points(stride(from: 9000, to: 12000, by: 60), 60)
        let logged = [points(stride(from: 0, to: 12000, by: 300), 70)]
        let runs = ChartLine.filled(recorded, gap: 150, logged: logged)
        #expect(runs.count == 1, "logged points bridge the recorded gap")
        let line = runs[0]
        #expect(line.map(\.t) == line.map(\.t).sorted())
        #expect(!line.contains { $0.avg == 70 && ($0.t < 3000 || $0.t > 9000) }, "covered logged points are dropped")
        #expect(line.contains { $0.avg == 70 && $0.t > 3000 && $0.t < 9000 })
    }

    @Test func twoRecordedRunsStayApartWithNothingLogged() {
        let recorded = points(stride(from: 0, to: 600, by: 60), 80) + points(stride(from: 800, to: 1400, by: 60), 80)
        #expect(ChartLine.filled(recorded, gap: 150, logged: []).count == 2)
    }

    @Test func loggedSegmentsKeepTheirOwnBreaks() {
        let logged = [points(stride(from: 0, to: 1500, by: 300), 50), points(stride(from: 20_000, to: 21_500, by: 300), 40)]
        #expect(ChartLine.filled([], gap: 900, logged: logged).count == 2)
    }

    @Test func batteryBeatRecordsChargeAndPower() {
        let h = ChartHistory()
        var s = BatterySnapshot()
        s.percent = 57
        s.systemLoadW = 12
        let at = Date(timeIntervalSinceReferenceDate: 1_000_000)
        h.recordBattery(s, at: at)
        #expect(h(.batteryCharge).points(.tenMinutes, now: at).map(\.avg) == [57])
        #expect(h(.powerSystem).points(.tenMinutes, now: at).map(\.avg) == [12])
    }

    @Test func powerItemAloneRecordsNoCharge() {
        let h = ChartHistory()
        var s = BatterySnapshot()
        s.percent = 57
        s.systemLoadW = 12
        h.recordPower(s, at: Date(timeIntervalSinceReferenceDate: 1_000_000))
        #expect(!h.recordedSeries.contains(.batteryCharge))
    }
}
