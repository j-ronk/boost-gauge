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
            #expect(a.system.points.map(\.value) == b.system.points.map(\.value))
            #expect(a.battery.points.map(\.value) == b.battery.points.map(\.value))
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

    @Test func powerHistoryEndsOnTheSnapshotReading() {
        for s in BatterySamples.all {
            let p = BatterySamples.powerHistory(s.snapshot, now: now)
            #expect(p.system.points.last?.value == s.snapshot.systemLoadW)
            #expect(abs((p.battery.points.last?.value ?? -1) - abs(s.snapshot.batteryW)) < 0.01, "\(s.name)")
            #expect(p.system.points.count == 61)
        }
    }

    /// Unplugged, the battery supplies the whole system, so the two lines sit on top of each other.
    @Test func onBatteryTheLinesTrackEachOther() {
        let p = BatterySamples.powerHistory(sample("on-battery-8").snapshot, now: now)
        for (sys, bat) in zip(p.system.points, p.battery.points) {
            #expect(abs(sys.value - bat.value) <= max(1.5, sys.value * 0.3))
        }
    }

    @Test func chargingSampleSwitchesFromTrackingToChargingAtPlugIn() {
        let s = sample("charging-34").snapshot
        let p = BatterySamples.powerHistory(s, now: now)
        let pairs = zip(p.system.points, p.battery.points)
        for (sys, bat) in pairs where now.timeIntervalSince(sys.date) > 300 {
            #expect(abs(sys.value - bat.value) <= max(1.5, sys.value * 0.3))
        }
        for (_, bat) in pairs where now.timeIntervalSince(bat.date) < 300 {
            #expect(abs(bat.value - s.batteryW) < 2)
        }
    }

    /// Real load holds a level, then jumps: a sine wave changes every sample.
    @Test func powerIsStepLikeNotAWave() {
        let p = BatterySamples.powerHistory(sample("charging-34").snapshot, now: now)
        let v = p.system.points.map(\.value)
        let steps = zip(v, v.dropFirst()).map { abs($1 - $0) / max($0, 1) }
        #expect(steps.filter { $0 < 0.06 }.count > 40, "mostly flat stretches")
        #expect(steps.contains { $0 > 0.8 }, "at least one sudden jump")
    }

    @Test func renderNowIsAMidAfternoonInThePast() {
        let r = BatterySamples.renderNow(raw)
        #expect(r <= raw)
        #expect(raw.timeIntervalSince(r) < 86_400)
        let c = Calendar.current.dateComponents([.hour, .minute], from: r)
        #expect(c.hour == 15 && c.minute == 40)
    }
}
