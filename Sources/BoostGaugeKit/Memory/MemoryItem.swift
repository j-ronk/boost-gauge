import AppKit
import Observation
import SwiftUI

struct AppMemoryRow: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let bytes: UInt64
}

@MainActor @Observable final class MemoryModel {
    var stats: MemoryStats?
    var pressure: MemoryPressure?
    /// 0 to 100, for the chart's dashed line.
    var pressurePercent: Double?
    var swapBytes: UInt64?
    var topApps: [AppMemoryRow]?

    var labelValue: String { stats.map { Format.percent($0.usedPercent) } ?? "—" }
}

@MainActor public final class MemoryItem: BoostGaugeItem {
    public let id = ItemID.memory
    let model = MemoryModel()
    private let settings: AppSettings
    private let charts: ChartHistory
    private let read: () -> MemoryStats?
    private let readPressure: () -> Double?

    public convenience init(_ ctx: AppContext) {
        self.init(ctx, read: MemoryStats.read, readPressure: MemoryPressure.percent)
    }

    init(_ ctx: AppContext, read: @escaping () -> MemoryStats?, readPressure: @escaping () -> Double? = { nil }) {
        settings = ctx.settings
        charts = ctx.charts
        self.read = read
        self.readPressure = readPressure
    }

    public var label: AnyView {
        let model = model
        return AnyView(PercentLabel(caption: "RAM") { model.labelValue })
    }

    public var panel: AnyView {
        AnyView(MemoryPanel(model: model, settings: settings, charts: charts).refreshing(every: .seconds(3)) { [weak self] in await self?.refreshPanel() })
    }

    public func tick(now: Date) {
        let stats = read()
        if model.stats != stats { model.stats = stats }
        let pressure = readPressure()
        if model.pressurePercent != pressure { model.pressurePercent = pressure }
        charts.record(.memoryUsed, stats?.usedPercent, at: now)
        charts.record(.memoryPressure, pressure, at: now)
    }

    public func panelDidClose() {
        model.topApps = nil
    }

    public func renderVariants() async -> [RenderVariant] {
        await refreshPanel()
        let sample = MemoryModel()
        let gib = UInt64(1 << 30)
        sample.stats = MemoryStats(usedBytes: UInt64(7.8 * Double(gib)), totalBytes: 16 * gib, usedPercent: 49)
        sample.pressure = .normal
        sample.pressurePercent = 18
        sample.swapBytes = 0
        sample.topApps = [
            AppMemoryRow(id: "a", name: "Safari", icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"), bytes: 3_700 << 20),
            AppMemoryRow(id: "b", name: "Mail", icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Mail.app"), bytes: 1_100 << 20),
            AppMemoryRow(id: "c", name: "WindowServer", icon: NSWorkspace.shared.icon(for: .applicationBundle), bytes: 900 << 20),
        ]
        return [RenderVariant("live", label: label, panel: panel)]
            + RenderVariant.eachRange("sample", label: AnyView(StackedLabel(caption: "RAM", value: "49%", widest: "100%")),
                                      panel: MemoryPanel(model: sample, settings: settings, charts: ChartSamples.history))
    }

    func refreshPanel() async {
        model.stats = read()
        model.pressure = MemoryPressure.read()
        model.swapBytes = MemoryStats.swapUsedBytes()
        // The per-app rollup walks every process; skip it while the rows are hidden.
        guard settings.isSectionShown(.memoryTopApps) else {
            if model.topApps != nil { model.topApps = nil }
            return
        }
        let top = await Task.detached(priority: .utility) { MemoryTop.sample(n: 3) }.value
        guard !Task.isCancelled else { return }
        model.topApps = top.map { row in
            let who = AppIdentity.resolve(pid: row.pid)
            return AppMemoryRow(id: row.key, name: who.name, icon: who.icon, bytes: row.bytes)
        }
    }
}
