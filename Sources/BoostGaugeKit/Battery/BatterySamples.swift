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
        Sample(name: "charging-34", snapshot: make(34, onAC: true, charging: true, toFull: 42, mV: 11_900, mA: 2_600, load: 18.2, adapterIn: 49.6)),
        Sample(name: "draining-on-ac-31", snapshot: make(31, onAC: true, charging: true, mV: 10_850, mA: -3_100, load: 121.6, adapterIn: 88.2)),
        Sample(name: "charged-100", snapshot: make(100, onAC: true, charged: true, mV: 13_050, mA: 0, load: 12.0, adapterIn: 12.5)),
        Sample(name: "on-battery-8", snapshot: make(8, onAC: false, toEmpty: 23, mV: 10_400, mA: -1_400, load: 14.6)),
        Sample(name: "on-hold-80", snapshot: make(80, onAC: true, mV: 12_600, mA: 0, load: 11.0, adapterIn: 11.4, optimized: true)),
    ]

    /// One spinning and one idle fan, so renders show both the rpm and "Off" forms.
    static let fans = [FanReading(index: 0, rpm: 3454, min: 1200, max: 6000), FanReading(index: 1, rpm: 0, min: 1200, max: 6000)]

    /// Ten minutes of gently varying watts around the sample's reading, so renders show the chart.
    static func powerHistory(_ s: BatterySnapshot, now: Date = .now) -> PowerHistory {
        var h = PowerHistory()
        let base = s.systemLoadW ?? 10
        for i in stride(from: 600, through: 0, by: -10) {
            var p = s
            p.systemLoadW = max(2, base * (1 + 0.35 * sin(Double(i) / 45)))
            h.add(p, at: now.addingTimeInterval(-Double(i)))
        }
        return h
    }

    static func model(_ sample: Sample, now: Date = .now) -> BatteryModel {
        let m = BatteryModel(history: nil, fixedHistory: history(endingAt: sample.snapshot.percent, now: now), now: now)
        m.snapshot = sample.snapshot
        m.users = users
        m.usersLoaded = true
        m.fans = fans
        m.powerHistory = powerHistory(sample.snapshot, now: now)
        return m
    }

    /// A day of charge with an overnight sleep gap, so renders show the line breaking.
    private static func history(endingAt end: Int, now: Date) -> [ChargeSample] {
        var out: [ChargeSample] = []
        for m in stride(from: 24 * 60, through: 14 * 60, by: -5) {
            let t = Double(24 * 60 - m) / 600
            out.append(ChargeSample(date: now.addingTimeInterval(-Double(m) * 60), percent: Int(95 - 40 * t), charging: false))
        }
        for m in stride(from: 9 * 60, through: 0, by: -5) {
            let t = Double(9 * 60 - m) / Double(9 * 60)
            let p = t < 0.4 ? 50 + Int(100 * t) : 90 - Int(Double(90 - end) * (t - 0.4) / 0.6)
            out.append(ChargeSample(date: now.addingTimeInterval(-Double(m) * 60), percent: min(100, max(0, p)), charging: t < 0.4))
        }
        return out
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
