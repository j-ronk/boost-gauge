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
    var swapBytes: UInt64?
    var topApps: [AppMemoryRow]?

    var labelValue: String { stats.map { Format.percent($0.usedPercent) } ?? "—" }
}

@MainActor public final class MemoryItem: BoostGaugeItem {
    public let id = ItemID.memory
    let model = MemoryModel()
    private let read: () -> MemoryStats?

    public convenience init(_ ctx: AppContext) {
        self.init(ctx, read: MemoryStats.read)
    }

    init(_ ctx: AppContext, read: @escaping () -> MemoryStats?) {
        self.read = read
    }

    public var label: AnyView {
        let model = model
        return AnyView(PercentLabel(caption: "RAM") { model.labelValue })
    }

    public var panel: AnyView {
        AnyView(MemoryPanel(model: model).refreshing(every: .seconds(3)) { [weak self] in await self?.refreshPanel() })
    }

    public func tick(now: Date) {
        let stats = read()
        if model.stats != stats { model.stats = stats }
    }

    public func panelDidClose() {
        model.topApps = nil
    }

    public func renderVariants() async -> [RenderVariant] {
        await refreshPanel()
        return [RenderVariant("live", label: label, panel: panel)]
    }

    func refreshPanel() async {
        model.stats = read()
        model.pressure = MemoryPressure.read()
        model.swapBytes = MemoryStats.swapUsedBytes()
        let top = await Task.detached(priority: .utility) { MemoryTop.sample(n: 3) }.value
        guard !Task.isCancelled else { return }
        model.topApps = top.map { row in
            let who = AppIdentity.resolve(pid: row.pid)
            return AppMemoryRow(id: row.key, name: who.name, icon: who.icon, bytes: row.bytes)
        }
    }
}
