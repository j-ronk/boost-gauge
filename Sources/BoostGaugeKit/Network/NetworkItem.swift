import Foundation
import Observation
import SwiftUI

@MainActor @Observable public final class NetworkItem: BoostGaugeItem {
    public let id: ItemID = .network
    let ctx: AppContext
    private(set) var rate: (up: Double, down: Double)?
    private(set) var connection: NetworkConnection?
    /// Where the speeds are recorded; render samples swap in their own.
    @ObservationIgnored var charts: ChartHistory
    @ObservationIgnored private var previous: (counters: [String: IfCounters], at: Date)?
    @ObservationIgnored private let snapshot: () -> [String: IfCounters]
    @ObservationIgnored private let readConnection: () -> NetworkConnection?

    public convenience init(_ ctx: AppContext) {
        self.init(ctx, snapshot: NetworkCounters.snapshot, readConnection: NetworkConnection.primary)
    }

    init(_ ctx: AppContext, snapshot: @escaping () -> [String: IfCounters],
         readConnection: @escaping () -> NetworkConnection? = { nil }) {
        self.ctx = ctx
        charts = ctx.charts
        self.snapshot = snapshot
        self.readConnection = readConnection
    }

    public var label: AnyView { AnyView(NetworkLabel(item: self)) }
    public var panel: AnyView { AnyView(NetworkPanel(item: self)) }

    /// A gap longer than a couple of intervals means the item was hidden or the Mac slept. The first tick back
    /// only re-baselines, so the label never shows an average over the whole gap.
    public func tick(now: Date) {
        let current = snapshot()
        defer { previous = (current, now) }
        guard let previous else { rate = nil; return }
        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0, elapsed <= staleAfter else { rate = nil; return }
        let r = NetworkCounters.rates(previous: previous.counters, current: current, elapsed: elapsed)
        rate = r
        charts.record(.networkDown, r.down, at: now)
        charts.record(.networkUp, r.up, at: now)
    }

    private var staleAfter: TimeInterval { max(Double(ctx.settings.refreshSeconds) * 2.5, 5) }

    func refreshPanel() {
        connection = readConnection()
    }

    var unit: NetworkUnit { ctx.settings.networkUnit }

    var labelLines: (String, String) {
        guard let rate else { return ("↑ —", "↓ —") }
        return ("↑ " + NetworkCounters.compact(rate.up, unit: unit), "↓ " + NetworkCounters.compact(rate.down, unit: unit))
    }

    var labelWidest: String { unit == .bits ? "↓ 999Mb" : "↓ 999M" }

    public func renderVariants() async -> [RenderVariant] {
        let sample = Self.sample(ctx)
        return [RenderVariant("live", label: label, panel: panel)]
            + RenderVariant.eachRange("sample", label: sample.label, panel: sample.panel)
    }

    /// Everyday traffic for the legend and header: background trickle, a few page loads, one big download and one
    /// upload; seeded so every render matches. The chart draws the shared render sample history.
    private static func sample(_ ctx: AppContext) -> NetworkItem {
        var received: UInt64 = 0, sent: UInt64 = 0, step = 0
        var rng = SampleRandom(seed: 11)
        let pageLoads: Set<Int> = [22, 23, 64, 118, 119, 120, 205, 262, 263]
        let item = NetworkItem(ctx, snapshot: {
            step += 1
            var down = rng.uniform(15_000...70_000), up = rng.uniform(4_000...20_000)
            if pageLoads.contains(step) { down += rng.uniform(1_500_000...4_000_000); up += rng.uniform(40_000...120_000) }
            if (140..<172).contains(step) { down += rng.uniform(16_000_000...22_000_000) }
            if (228..<246).contains(step) { up += rng.uniform(1_800_000...2_600_000) }
            received += UInt64(down)
            sent += UInt64(up)
            return ["en0": IfCounters(ibytes: received, obytes: sent)]
        }, readConnection: { NetworkConnection(service: "Wi-Fi", interface: "en0", address: "192.168.1.20") })
        item.charts = ChartHistory()
        let end = Date.now
        for i in stride(from: 300, through: 0, by: -1) {
            item.tick(now: end.addingTimeInterval(TimeInterval(-2 * i)))
        }
        item.charts = ChartSamples.history
        return item
    }
}

struct NetworkLabel: View {
    let item: NetworkItem

    var body: some View {
        let lines = item.labelLines
        StackedLabel(top: lines.0, bottom: lines.1, widest: item.labelWidest)
    }
}
