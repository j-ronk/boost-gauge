import SwiftUI

/// A seeded day of every series for `--render`, ending on the README's sample figures. The app wasn't running
/// for two hours overnight, so 24 Hours shows a gap.
@MainActor enum ChartSamples {
    static let history: ChartHistory = make(now: .now)

    static func make(now: Date) -> ChartHistory {
        let h = ChartHistory()
        func fill(_ id: ChartSeriesID, _ seed: UInt64, _ base: Double, _ amp: Double, _ end: Double,
                  _ range: ClosedRange<Double> = 0...100, spikes: Double = 0.004, night: Double = 0.6) {
            Self.fill(h, id, seed: seed, base: base, amp: amp, end: end, range: range, spikes: spikes, night: night,
                      until: now)
        }
        fill(.cpu, 1, 20, 10, 23)
        fill(.gpu, 2, 30, 25, 100)
        fill(.memoryUsed, 3, 47, 2, 49, spikes: 0, night: 0.95)
        fill(.memoryPressure, 4, 16, 3, 18, spikes: 0, night: 0.9)
        fill(.networkDown, 5, 300_000, 400_000, 15_000, 0...25_000_000, spikes: 0.01)
        fill(.networkUp, 6, 60_000, 60_000, 9_000, 0...25_000_000, spikes: 0.006)
        fill(.diskRead, 7, 1_500_000, 2_000_000, 12_300_000, 0...200_000_000, spikes: 0.01)
        fill(.diskWrite, 8, 600_000, 800_000, 650_000, 0...200_000_000, spikes: 0.008)
        fill(.tempsHottest, 9, 66, 4, 72, 30...100, night: 0.85)
        fill(.tempsCPU, 10, 54, 4, 58, 30...100, night: 0.85)
        fill(.tempsGPU, 12, 51, 3, 54, 30...100, night: 0.85)
        fill(.powerSystem, 13, 15, 5, 18.2, 0...200)
        fill(.powerBattery, 14, 28, 2, 30.9, 0...200)
        return h
    }

    /// A smoothed random walk with short bursts, scaled down to `night` at 4 am, ending on `end`: readings
    /// every 2 s for the last hour and every 10 s before, none from 9 to 7 hours ago.
    static func fill(_ h: ChartHistory, _ id: ChartSeriesID, seed: UInt64, base: Double, amp: Double, end: Double,
                     range: ClosedRange<Double>, spikes: Double = 0.004, night: Double = 0.6, until now: Date) {
        var rng = SampleRandom(seed: seed)
        let series = h(id)
        var v = base
        var burst = 0
        var t = -86_400.0
        while t <= 0 {
            let step: Double = t < -3600 ? 10 : 2
            defer { t += step }
            if t > -9 * 3600, t < -7 * 3600 { continue }
            let clock = Calendar.current.dateComponents([.hour, .minute], from: now.addingTimeInterval(t))
            let hour = Double(clock.hour ?? 12) + Double(clock.minute ?? 0) / 60
            // Busiest mid-afternoon, quietest at 4 am, with no step anywhere.
            var target = base * (night + (1 - night) * (0.5 - 0.5 * cos(2 * .pi * (hour - 4) / 24)))
            // The last hour drifts onto the live figure, so 24 Hours ends where the panel's header does.
            if t > -3600 { target += (end - target) * (1 + t / 3600) }
            v = v * 0.8 + (target + rng.uniform(-1...1) * amp) * 0.2
            if burst == 0, rng.uniform(0...1) < spikes * step / 2 { burst = Int(rng.uniform(4...20) * 2 / step) + 1 }
            var x = v
            if burst > 0 { x += amp * 2.4; burst -= 1 }
            // The last half minute eases onto the panel's live figure.
            if t > -30 { x += (end - x) * (1 - (-t / 30)) }
            series.record(min(range.upperBound, max(range.lowerBound, x)), at: now.addingTimeInterval(t))
        }
    }
}

extension RenderVariant {
    /// The same panel at each chart range: `name` at 10 Min, then `name-1h` and `name-24h`.
    @MainActor static func eachRange(_ name: String, label: AnyView, panel: some View) -> [RenderVariant] {
        ChartRange.allCases.map { range in
            RenderVariant(range == .tenMinutes ? name : "\(name)-\(range.rawValue)", label: label,
                          panel: AnyView(panel.environment(\.chartRangeOverride, range)))
        }
    }
}
