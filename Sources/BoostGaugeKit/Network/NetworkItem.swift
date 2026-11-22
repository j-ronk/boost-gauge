import Foundation
import Observation
import SwiftUI

@MainActor @Observable public final class NetworkItem: BoostGaugeItem {
    public let id: ItemID = .network
    let ctx: AppContext
    private(set) var rate: (up: Double, down: Double)?
    private(set) var up = TimeSeries()
    private(set) var down = TimeSeries()
    private(set) var connection: NetworkConnection?
    @ObservationIgnored private var previous: (counters: [String: IfCounters], at: Date)?
    @ObservationIgnored private let snapshot: () -> [String: IfCounters]
    @ObservationIgnored private let readConnection: () -> NetworkConnection?

    public convenience init(_ ctx: AppContext) {
        self.init(ctx, snapshot: NetworkCounters.snapshot, readConnection: NetworkConnection.primary)
    }

    init(_ ctx: AppContext, snapshot: @escaping () -> [String: IfCounters],
         readConnection: @escaping () -> NetworkConnection? = { nil }) {
        self.ctx = ctx
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
        up.append(r.up, at: now)
        down.append(r.down, at: now)
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
        [RenderVariant("live", label: label, panel: panel), Self.sample(ctx).variant]
    }

    /// Ten minutes of made-up traffic, so the chart's shape and legend can be checked; live renders have two points.
    private static func sample(_ ctx: AppContext) -> (item: NetworkItem, variant: RenderVariant) {
        var received: UInt64 = 0, sent: UInt64 = 0, step = 0
        let item = NetworkItem(ctx, snapshot: {
            step += 1
            let wave = (sin(Double(step) / 18) + 1) / 2
            received += UInt64(2_000_000 * wave + (step % 40 < 6 ? 6_000_000 : 40_000))
            sent += UInt64(180_000 * (1 - wave) + 12_000)
            return ["en0": IfCounters(ibytes: received, obytes: sent)]
        }, readConnection: { NetworkConnection(service: "Wi-Fi", interface: "en0", address: "192.168.1.20") })
        let end = Date.now
        for i in stride(from: 300, through: 0, by: -1) {
            item.tick(now: end.addingTimeInterval(TimeInterval(-2 * i)))
        }
        return (item, RenderVariant("sample", label: item.label, panel: item.panel))
    }
}

struct NetworkLabel: View {
    let item: NetworkItem

    var body: some View {
        let lines = item.labelLines
        StackedLabel(top: lines.0, bottom: lines.1, widest: item.labelWidest)
    }
}
