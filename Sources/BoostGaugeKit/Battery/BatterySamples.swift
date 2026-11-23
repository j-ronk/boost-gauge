import AppKit
import SwiftUI

/// Fixed states for `--render`, mirroring the Battery test fixtures (which ship only in the test bundle).
@MainActor enum BatterySamples {
    struct Sample {
        let name: String
        let snapshot: BatterySnapshot
    }

    private static func make(_ percent: Int, onAC: Bool, charging: Bool = false, charged: Bool = false,
                             toFull: Int? = nil, toEmpty: Int? = nil, mV: Int, mA: Int,
                             load: Double, adapterIn: Double? = nil, optimized: Bool = false) -> BatterySnapshot {
        var s = BatterySnapshot()
        s.percent = percent
        s.onAC = onAC
        s.isCharging = charging
        s.isCharged = charged
        s.minutesToFull = toFull
        s.minutesToEmpty = toEmpty
        s.voltage_mV = mV
        s.amperage_mA = mA
        s.systemLoadW = load
        s.adapterInW = onAC ? adapterIn : nil
        s.adapterRatedW = onAC ? 94 : nil
        s.designCapacity = 8694
        s.nominalCapacity = 7757
        s.rawMaxCapacity = 7513
        s.cycleCount = 197
        s.temperatureC = 31.4
        s.optimizedChargingEngaged = optimized
        return s
    }

    static let all: [Sample] = [
        // 66% of 7,513 mAh at 2.6 A is about 1:54 to full.
        Sample(name: "charging-34", snapshot: make(34, onAC: true, charging: true, toFull: 114, mV: 11_900, mA: 2_600, load: 18.2, adapterIn: 49.6)),
        Sample(name: "draining-on-ac-31", snapshot: make(31, onAC: true, charging: true, mV: 10_850, mA: -3_100, load: 121.6, adapterIn: 88.2)),
        Sample(name: "charged-100", snapshot: make(100, onAC: true, charged: true, mV: 13_050, mA: 0, load: 12.0, adapterIn: 12.5)),
        Sample(name: "on-battery-8", snapshot: make(8, onAC: false, toEmpty: 23, mV: 10_400, mA: -1_400, load: 14.6)),
        Sample(name: "on-hold-80", snapshot: make(80, onAC: true, mV: 12_600, mA: 0, load: 11.0, adapterIn: 11.4, optimized: true)),
    ]

    /// One spinning and one idle fan, so renders show both the rpm and "Off" forms.
    static let fans = [FanReading(index: 0, rpm: 3454, min: 1200, max: 6000), FanReading(index: 1, rpm: 0, min: 1200, max: 6000)]

    /// A day of everyday load, then ten minutes of step-like load: plateaus, a burst, a brief dip, a little noise,
    /// ending on the sample's reading. A charging sample was plugged in five minutes ago, so before that the battery
    /// line tracks the system line.
    static func powerHistory(_ s: BatterySnapshot, now: Date = .now) -> ChartHistory {
        var rng = SampleRandom(seed: UInt64(s.percent))
        let load = s.systemLoadW ?? 10
        let volts = Double(s.voltage_mV) / 1000
        let pluggedInAt: Double? = s.onAC && s.amperage_mA > 0 ? -300 : nil
        // (ten-second steps, multiple of the final load)
        let script: [(Int, Double)] = [(6, 0.55), (5, 0.7), (1, 0.4), (7, 0.6), (9, 2.3), (4, 1.6), (8, 0.75), (1, 0.5),
                                       (6, 0.9), (14, 1.0)]
        let multiples = script.flatMap { Array(repeating: $0.1, count: $0.0) }
        // A Mac already near its limit can't burst much higher, so heavy loads keep their steps close together.
        let spread = load > 60 ? 0.15 : 1
        let h = ChartHistory()
        let load0 = load * (1 + (multiples[0] - 1) * spread)
        ChartSamples.fill(h, .powerSystem, seed: UInt64(s.percent) + 100, base: load0, amp: load0 * 0.4,
                          end: load0, range: 0...200, until: now.addingTimeInterval(-600))
        ChartSamples.fill(h, .powerBattery, seed: UInt64(s.percent) + 200, base: abs(s.batteryW), amp: abs(s.batteryW) * 0.2,
                          end: abs(s.batteryW), range: 0...200, until: now.addingTimeInterval(-600))
        var previous = load * (1 + (multiples[0] - 1) * spread)
        for (i, multiple) in multiples.enumerated() {
            let offset = Double(i * 10 - 600)
            let date = now.addingTimeInterval(offset)
            guard offset < 0 else { h.recordPower(s, at: date); break }
            let level = load * (1 + (multiple - 1) * spread) * (1 + rng.uniform(-0.025...0.025))
            let onAC = s.onAC && offset >= (pluggedInAt ?? -.infinity)
            let batteryW: Double
            if !onAC {
                // The battery reading lags the system one by a sample.
                batteryW = -(0.85 * level + 0.15 * previous) * (1 + rng.uniform(-0.03...0.03))
            } else if s.amperage_mA > 0 {
                batteryW = s.batteryW * (1 + rng.uniform(-0.02...0.02))
            } else if s.amperage_mA < 0 {
                batteryW = (s.adapterInW ?? 0) - level
            } else {
                batteryW = 0
            }
            var p = s
            p.onAC = onAC
            p.systemLoadW = level
            p.amperage_mA = Int((batteryW / volts * 1000).rounded())
            // Readings every two seconds, as the menu bar takes them at the default refresh.
            for k in 0..<5 { h.recordPower(p, at: date.addingTimeInterval(Double(2 * k))) }
            previous = level
        }
        return h
    }

    static func model(_ sample: Sample, now: Date = .now) -> BatteryModel {
        let at = renderNow(now)
        let m = BatteryModel(history: nil, fixedHistory: history(for: sample, now: at), now: at)
        m.snapshot = sample.snapshot
        m.users = users
        m.usersLoaded = true
        m.fans = fans
        m.powerCharts = powerHistory(sample.snapshot, now: ChartSamples.now)
        return m
    }

    /// The most recent 15:40, so the day chart's overnight sleep lands at night on its axis whenever the render runs.
    nonisolated static func renderNow(_ now: Date = .now) -> Date {
        let cal = Calendar.current
        let today = cal.date(bySettingHour: 15, minute: 40, second: 0, of: now)!
        return today <= now ? today : cal.date(byAdding: .day, value: -1, to: today)!
    }

    /// One charge reading a minute, as the history file keeps them, built forward through the day.
    private struct Timeline {
        var date: Date
        var percent: Double
        var rng: SampleRandom
        var out: [ChargeSample] = []

        mutating func emit(charging: Bool) {
            out.append(ChargeSample(date: date, percent: Int(percent.rounded()), charging: charging))
        }

        /// On the charger at 80% or full, or a sample that's done.
        mutating func hold(until end: Date) {
            while date < end {
                emit(charging: false)
                date += 60
            }
        }

        /// Asleep: no readings, so the chart breaks its line.
        mutating func sleep(until end: Date) { date = end }

        /// Uneven slopes landing on `target` at `end`: heavier and lighter stretches, now and then a near-idle one.
        mutating func move(to target: Double, until end: Date, charging: Bool = false) {
            var chunks: [(end: Date, weight: Double)] = []
            var t = date
            while t < end {
                let next = min(end, t.addingTimeInterval(rng.uniform(25...70).rounded() * 60))
                let pace = rng.uniform(0...1) < 0.2 ? 0.1 : rng.uniform(0.5...1.8)
                chunks.append((next, pace * next.timeIntervalSince(t)))
                t = next
            }
            let total = chunks.reduce(0) { $0 + $1.weight }
            let change = target - percent
            for chunk in chunks {
                let chunkTarget = percent + change * chunk.weight / total
                let step = (chunkTarget - percent) / max(1, chunk.end.timeIntervalSince(date) / 60)
                while date < chunk.end {
                    emit(charging: charging)
                    percent += step
                    date += 60
                }
                percent = chunkTarget
            }
            percent = target
        }

        /// Quick to about 80%, then slower and slower to the top.
        mutating func charge(to target: Double) {
            while percent < target - 0.01 {
                emit(charging: true)
                let pace = percent < 80 ? 0.95 - 0.0035 * percent : max(0.12, 0.67 * (100 - percent) / 20)
                percent = min(target, percent + pace * rng.uniform(0.85...1.15))
                date += 60
            }
            percent = target
        }
    }

    /// One past day: off the charger mid-morning, maybe a lunchtime top-up, plugged in at night, asleep at 23:15.
    private struct Day {
        var unplug: Double
        var lunch: Double? = nil
        var topUp: Double? = nil
        var evening: Double
        var plugIn: Double
        var night: Double = 80
    }

    /// Ten days, oldest first. The two desk days stay on the charger until evening; one night charges to full.
    private static let days: [Day] = [
        Day(unplug: 8.75, lunch: 52, evening: 24, plugIn: 18.5),
        Day(unplug: 9.25, lunch: 61, topUp: 78, evening: 35, plugIn: 21),
        Day(unplug: 18.5, evening: 55, plugIn: 22),
        Day(unplug: 8.5, lunch: 44, topUp: 70, evening: 18, plugIn: 19.25, night: 100),
        Day(unplug: 10.5, lunch: 88, evening: 52, plugIn: 22.5),
        Day(unplug: 11, lunch: 70, evening: 41, plugIn: 21.5),
        Day(unplug: 8.75, lunch: 55, evening: 27, plugIn: 18),
        Day(unplug: 18, evening: 60, plugIn: 21.75),
        Day(unplug: 9, lunch: 58, topUp: 80, evening: 30, plugIn: 20.5),
        Day(unplug: 8.9, lunch: 49, evening: 22, plugIn: 20),
    ]

    /// Ten days of charge ending on the sample: each morning starts on the charger at 80%, and today ends in the
    /// sample's state (charging-34 was plugged in at 31% five minutes ago).
    static func history(for sample: Sample, now: Date) -> [ChargeSample] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func at(_ day: Date, _ hours: Double) -> Date {
            let minutes = Int((hours * 60).rounded())
            return cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)!
        }
        var t = Timeline(date: at(cal.date(byAdding: .day, value: -days.count, to: today)!, 7.75), percent: 80,
                         rng: SampleRandom(seed: 2026))
        for (i, day) in days.enumerated() {
            let date = cal.date(byAdding: .day, value: i - days.count, to: today)!
            t.hold(until: at(date, day.unplug))
            if let lunch = day.lunch {
                t.move(to: lunch, until: at(date, 12.5))
                if let topUp = day.topUp { t.charge(to: topUp) }
            }
            t.move(to: day.evening, until: at(date, day.plugIn))
            t.charge(to: day.night)
            t.hold(until: at(date, 23.25))
            t.sleep(until: at(cal.date(byAdding: .day, value: 1, to: date)!, 7.75))
        }
        switch sample.name {
        case "charging-34":
            t.hold(until: at(today, 12.67))
            t.move(to: 31, until: now.addingTimeInterval(-300))
            t.move(to: 34, until: now, charging: true)
        case "draining-on-ac-31":
            t.hold(until: at(today, 11.5))
            t.move(to: 40, until: at(today, 14.83))
            t.move(to: 31, until: now)
        case "charged-100":
            t.hold(until: at(today, 9.17))
            t.move(to: 46, until: at(today, 13.08))
            t.charge(to: 100)
        case "on-battery-8":
            t.hold(until: at(today, 8.67))
            t.move(to: 8, until: now)
        default:
            break
        }
        t.hold(until: now)
        t.date = now
        t.percent = Double(sample.snapshot.percent)
        var charging = false
        if case .charging = ChargeState.classify(sample.snapshot) { charging = true }
        t.emit(charging: charging)
        return t.out
    }

    private static var users: [EnergyUser] {
        let apps: [(String, String, Double)] = [
            ("/Applications/Safari.app", "Safari", 21.4),
            ("/System/Applications/Mail.app", "Mail", 6.2),
            ("/System/Applications/Music.app", "Music", 3.8),
            ("/System/Library/CoreServices/Finder.app", "Finder", 1.1),
            ("/System/Applications/Notes.app", "Notes", 0.4),
        ]
        return apps.map { EnergyUser(id: $0.0, name: $0.1, icon: NSWorkspace.shared.icon(forFile: $0.0), impact: $0.2) }
    }

    /// Every level and glyph side by side, to check the fill steps smoothly and the glyphs read.
    struct LevelStrip: View {
        var showPercentage = true
        var lowPower = false
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            let tint: BatteryTint = lowPower ? .lowPower(dark: scheme == .dark) : .template
            HStack(spacing: 10) {
                // On battery 5, 20, 54 and 100; charging 34; on hold at 80 and charged at 100 show the same bolt.
                ForEach(Array([(5, BatteryGlyph.none), (20, .none), (54, .none), (34, .bolt), (80, .bolt), (100, .bolt),
                               (100, .none)].enumerated()), id: \.offset) { _, level in
                    Image(nsImage: BatteryIcon.label(percent: level.0, glyph: level.1, showPercentage: showPercentage,
                                                     tint: tint))
                        .renderingMode(lowPower ? .original : .template)
                }
            }
        }
    }

    /// The low-battery cases: 11% normal, 10% and 3% red, charging and on hold at 8% normal with the bolt,
    /// Low Power at 8% yellow.
    struct LowBatteryStrip: View {
        var showPercentage = true
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            let cases: [(Int, BatteryGlyph, Bool)] = [(11, .none, false), (10, .none, false), (3, .none, false),
                                                      (8, .bolt, false), (8, .none, true)]
            HStack(spacing: 10) {
                ForEach(Array(cases.enumerated()), id: \.offset) { _, c in
                    let tint = BatteryIcon.tint(percent: c.0, glyph: c.1, lowPower: c.2, dark: scheme == .dark)
                    Image(nsImage: BatteryIcon.label(percent: c.0, glyph: c.1, showPercentage: showPercentage, tint: tint))
                        .renderingMode(tint == .template ? .template : .original)
                }
            }
        }
    }

    /// The stepped SF Symbol batteries at the same scale, for comparison with the hand-drawn icon.
    struct SFSymbolStrip: View {
        var body: some View {
            HStack(spacing: 10) {
                ForEach(["battery.0percent", "battery.25percent", "battery.50percent", "battery.75percent",
                         "battery.100percent", "battery.100percent.bolt"], id: \.self) { name in
                    Image(systemName: name)
                }
            }
        }
    }
}
