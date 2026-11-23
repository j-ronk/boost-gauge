import Foundation
import Observation
import SwiftUI

@MainActor @Observable public final class DiskItem: BoostGaugeItem {
    public let id: ItemID = .disk
    let ctx: AppContext
    private(set) var capacity: DiskCapacity?
    private(set) var activity: (read: Double, write: Double)?
    @ObservationIgnored private(set) var capacityRefresh: Task<Void, Never>?
    @ObservationIgnored private var lastCapacityRead: Date?
    @ObservationIgnored private var previousTotals: (totals: (read: UInt64, write: UInt64), at: Date)?
    /// Where read and write speeds are recorded; render samples swap in their own.
    @ObservationIgnored var charts: ChartHistory
    @ObservationIgnored private let readCapacity: @Sendable () -> DiskCapacity?
    @ObservationIgnored private let readTotals: () -> (read: UInt64, write: UInt64)

    public convenience init(_ ctx: AppContext) {
        self.init(ctx, readCapacity: { DiskCapacity.startupVolume() }, readTotals: DiskStats.readTotals)
    }

    init(_ ctx: AppContext, readCapacity: @escaping @Sendable () -> DiskCapacity?,
         readTotals: @escaping () -> (read: UInt64, write: UInt64)) {
        self.ctx = ctx
        charts = ctx.charts
        self.readCapacity = readCapacity
        self.readTotals = readTotals
    }

    public var label: AnyView { AnyView(DiskLabel(item: self)) }
    public var panel: AnyView { AnyView(DiskPanel(item: self)) }

    public func tick(now: Date) {
        refreshCapacity(now: now, force: false)
        sampleActivity(now: now)
    }

    public func panelDidOpen() {
        refreshCapacity(now: .now, force: true)
    }

    /// Read and write rates from the menu bar tick, for the chart. A gap longer than a couple of intervals (hidden,
    /// asleep) only re-baselines, so no rate is an average over the whole gap.
    func sampleActivity(now: Date) {
        let current = readTotals()
        defer { previousTotals = (current, now) }
        guard let previous = previousTotals else { activity = nil; return }
        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0, elapsed <= staleAfter else { activity = nil; return }
        let rates = DiskStats.rates(previous: previous.totals, current: current, elapsed: elapsed)
        activity = rates
        charts.record(.diskRead, rates.read, at: now)
        charts.record(.diskWrite, rates.write, at: now)
    }

    private var staleAfter: TimeInterval { max(Double(ctx.settings.refreshSeconds) * 2.5, 5) }

    /// Free space barely moves and Finder's figure is slow to compute, so the label re-reads it at most once a minute.
    private func refreshCapacity(now: Date, force: Bool) {
        if !force, let last = lastCapacityRead, now.timeIntervalSince(last) < 60 { return }
        lastCapacityRead = now
        let read = readCapacity
        capacityRefresh = Task { [weak self] in
            let value = await Task.detached(priority: .utility) { read() }.value
            if let value { self?.capacity = value }
        }
    }

    var labelValue: String { capacity.map { DiskStats.freeLabel($0.available) } ?? "—" }

    public func renderVariants() async -> [RenderVariant] {
        await capacityRefresh?.value
        // Live renders open the panel for a moment only, so rates are staged to check that section's layout.
        var read: UInt64 = 0
        let sample = DiskItem(ctx, readCapacity: { DiskCapacity(name: "Macintosh HD", available: 412_300_000_000, total: 994_662_584_320) },
                              readTotals: { read += 1; return (read * 24_600_000, read * 1_300_000) })
        sample.charts = ChartHistory()
        sample.tick(now: .now.addingTimeInterval(-2))
        await sample.capacityRefresh?.value
        sample.sampleActivity(now: .now)
        sample.charts = ChartSamples.history
        return [RenderVariant("live", label: label, panel: panel)]
            + RenderVariant.eachRange("sample", label: sample.label, panel: DiskPanel(item: sample))
    }
}

struct DiskLabel: View {
    let item: DiskItem

    var body: some View {
        // "999G" is the widest value; "9.9T" in the plan is narrower than the "412G" this Mac shows.
        StackedLabel(caption: "SSD", value: item.labelValue, widest: "999G")
    }
}
