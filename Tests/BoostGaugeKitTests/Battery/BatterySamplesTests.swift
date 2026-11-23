import Foundation
import Testing
@testable import BoostGaugeKit

/// The `--render` samples feed the README screenshots, so they must look like a real Mac and agree with the panel.
@MainActor
struct BatterySamplesTests {
    private let raw = Date(timeIntervalSince1970: 1_800_000_000)
    private var now: Date { BatterySamples.renderNow(raw) }

    private func sample(_ name: String) -> BatterySamples.Sample {
        BatterySamples.all.first { $0.name == name }!
    }

    @Test func sameRenderEveryRun() {
        for s in BatterySamples.all {
            #expect(BatterySamples.history(for: s, now: now) == BatterySamples.history(for: s, now: now))
            let a = BatterySamples.powerHistory(s.snapshot, now: now), b = BatterySamples.powerHistory(s.snapshot, now: now)
            for range in ChartRange.allCases {
                #expect(a(.powerSystem).points(range, now: now) == b(.powerSystem).points(range, now: now))
                #expect(a(.powerBattery).points(range, now: now) == b(.powerBattery).points(range, now: now))
            }
        }
    }

    @Test func historyEndsAtTheSnapshot() {
        for s in BatterySamples.all {
            let h = BatterySamples.history(for: s, now: now)
            #expect(h.last?.date == now)
            #expect(h.last?.percent == s.snapshot.percent, "\(s.name)")
            var charging = false
            if case .charging = ChargeState.classify(s.snapshot) { charging = true }
            #expect(h.last?.charging == charging, "\(s.name)")
            #expect(h.allSatisfy { (0...100).contains($0.percent) })
            #expect(zip(h, h.dropFirst()).allSatisfy { $0.date < $1.date })
        }
    }

    @Test func historyCoversTenDaysWithOvernightGaps() {
        let h = BatterySamples.history(for: sample("charging-34"), now: now)
        let first = try! #require(h.first)
        #expect(now.timeIntervalSince(first.date) > 9.5 * 86_400)
        let day = HistoryStore.series(of: h, .day, now: now)
        let tenDays = HistoryStore.series(of: h, .tenDays, now: now)
        #expect(day.count == 2, "one overnight sleep in the last 24 hours")
        #expect((9...11).contains(tenDays.count), "a sleep each night")
    }

    /// Charge moves a point or so a minute at most; a real battery never jumps.
    @Test func historyMovesSmoothly() {
        for s in BatterySamples.all {
            let h = BatterySamples.history(for: s, now: now)
            for (a, b) in zip(h, h.dropFirst()) where b.date.timeIntervalSince(a.date) <= 120 {
                #expect(abs(b.percent - a.percent) <= 2, "\(s.name) at \(b.date)")
            }
        }
    }

    @Test func chargingSampleWasPluggedInFiveMinutesAgo() {
        let h = BatterySamples.history(for: sample("charging-34"), now: now)
        let recent = h.filter { now.timeIntervalSince($0.date) <= 300 }
        #expect(recent.allSatisfy { $0.charging })
        #expect((30...32).contains(recent.first!.percent))
        let before = h.last { now.timeIntervalSince($0.date) > 330 }!
        #expect(!before.charging)
    }

    @Test func historySitsOnTheChargerAtEightyAndHundred() {
        let h = BatterySamples.history(for: sample("charging-34"), now: now)
        func flatHours(at p: Int) -> Double {
            Double(h.filter { $0.percent == p && !$0.charging }.count) / 60
        }
        #expect(flatHours(at: 80) > 6)
        #expect(flatHours(at: 100) > 1)
    }

    /// The scripted last ten minutes: a level every ten seconds, read every two.
    private func tenMinutes(_ s: BatterySnapshot) -> (system: [ChartPoint], battery: [ChartPoint]) {
        let h = BatterySamples.powerHistory(s, now: now)
        return (h(.powerSystem).points(.tenMinutes, now: now), h(.powerBattery).points(.tenMinutes, now: now))
    }

    private func age(_ p: ChartPoint) -> TimeInterval { now.timeIntervalSinceReferenceDate - p.t }

    @Test func powerHistoryEndsOnTheSnapshotReading() {
        for s in BatterySamples.all {
            let p = tenMinutes(s.snapshot)
            #expect(p.system.last.map { Double($0.avg) } == s.snapshot.systemLoadW.map { Double(Float($0)) })
            #expect(abs(Double(p.battery.last?.avg ?? -1) - abs(s.snapshot.batteryW)) < 0.01, "\(s.name)")
            #expect(p.system.count == 300)
        }
    }

    /// A whole day behind the scripted ten minutes, with the overnight gap, so every range has a line.
    @Test func powerHistoryCoversTheDay() {
        let h = BatterySamples.powerHistory(sample("charging-34").snapshot, now: now)
        let day = h(.powerSystem).points(.day, now: now)
        #expect(day.count > 150)
        let gaps = zip(day, day.dropFirst()).filter { $1.t - $0.t > 3600 }
        #expect(gaps.count == 1)
        #expect(h(.powerBattery).points(.hour, now: now).count > 200)
    }

    /// Unplugged, the battery supplies the whole system, so the two lines sit on top of each other.
    @Test func onBatteryTheLinesTrackEachOther() {
        let p = tenMinutes(sample("on-battery-8").snapshot)
        for (sys, bat) in zip(p.system, p.battery) {
            #expect(abs(sys.avg - bat.avg) <= max(1.5, sys.avg * 0.3))
        }
    }

    @Test func chargingSampleSwitchesFromTrackingToChargingAtPlugIn() {
        let s = sample("charging-34").snapshot
        let p = tenMinutes(s)
        let pairs = zip(p.system, p.battery)
        for (sys, bat) in pairs where age(sys) > 301 {
            #expect(abs(sys.avg - bat.avg) <= max(1.5, sys.avg * 0.3))
        }
        for (_, bat) in pairs where age(bat) < 299 {
            #expect(abs(Double(bat.avg) - s.batteryW) < 2)
        }
    }

    /// Real load holds a level, then jumps: a sine wave changes every sample.
    @Test func powerIsStepLikeNotAWave() {
        let v = tenMinutes(sample("charging-34").snapshot).system.map { Double($0.avg) }
        let steps = zip(v, v.dropFirst()).map { abs($1 - $0) / max($0, 1) }
        #expect(steps.filter { $0 < 0.06 }.count > 200, "mostly flat stretches")
        #expect(steps.contains { $0 > 0.8 }, "at least one sudden jump")
    }

    @Test func switchingRangeKeepsTheSampleClock() {
        let m = BatterySamples.model(sample("charging-34"), now: raw)
        m.historyRange = .tenDays
        #expect((9...11).contains(m.historySegments.count))
        m.historyRange = .day
        #expect(m.historySegments.count == 2)
    }

    @Test func renderNowIsAMidAfternoonInThePast() {
        let r = BatterySamples.renderNow(raw)
        #expect(r <= raw)
        #expect(raw.timeIntervalSince(r) < 86_400)
        let c = Calendar.current.dateComponents([.hour, .minute], from: r)
        #expect(c.hour == 15 && c.minute == 40)
    }
}
