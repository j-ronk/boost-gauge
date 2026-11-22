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
    @ObservationIgnored private let readCapacity: @Sendable () -> DiskCapacity?
    @ObservationIgnored private let readTotals: () -> (read: UInt64, write: UInt64)

    public convenience init(_ ctx: AppContext) {
        self.init(ctx, readCapacity: { DiskCapacity.startupVolume() }, readTotals: DiskStats.readTotals)
    }

    init(_ ctx: AppContext, readCapacity: @escaping @Sendable () -> DiskCapacity?,
         readTotals: @escaping () -> (read: UInt64, write: UInt64)) {
        self.ctx = ctx
        self.readCapacity = readCapacity
        self.readTotals = readTotals
    }

    public var label: AnyView { AnyView(DiskLabel(item: self)) }
    public var panel: AnyView { AnyView(DiskPanel(item: self)) }

    public func tick(now: Date) {
        refreshCapacity(now: now, force: false)
    }

    public func panelDidOpen() {
        refreshCapacity(now: .now, force: true)
    }

    /// Read and write rates exist only while the panel is open; closing it drops the baseline so the next open
    /// starts fresh instead of averaging over the time it was closed.
    public func panelDidClose() {
        previousTotals = nil
        activity = nil
    }

    func sampleActivity(now: Date) {
        let current = readTotals()
        defer { previousTotals = (current, now) }
        guard let previous = previousTotals else { return }
        activity = DiskStats.rates(previous: previous.totals, current: current, elapsed: now.timeIntervalSince(previous.at))
    }

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
        sample.tick(now: .now)
        await sample.capacityRefresh?.value
        sample.sampleActivity(now: .now.addingTimeInterval(-2))
        sample.sampleActivity(now: .now)
        return [
            RenderVariant("live", label: label, panel: panel),
            RenderVariant("sample", label: sample.label, panel: AnyView(DiskPanel(item: sample, samplesLive: false))),
        ]
    }
}

struct DiskLabel: View {
    let item: DiskItem

    var body: some View {
        // "999G" is the widest value; "9.9T" in the plan is narrower than the "412G" this Mac shows.
        StackedLabel(caption: "SSD", value: item.labelValue, widest: "999G")
    }
}
