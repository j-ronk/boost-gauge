import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One menu bar item for the whole Mac: a mini-bars glyph (CPU, GPU, memory) that opens a condensed panel of every
/// other item's headline figures. It reads nothing itself; the figures are the other items' own models.
@MainActor public final class OverviewItem: BoostGaugeItem {
    public let id = ItemID.overview
    let model = OverviewModel()

    /// The glyph needs these on every beat.
    static let glyphSources: [ItemID] = [.cpu, .gpu, .memory]
    /// The rest of the panel's figures, needed only while it's open.
    static let panelSources: [ItemID] = [.temps, .network, .disk]

    private let ctx: AppContext
    private let readBattery: (_ fresh: Bool) -> BatterySnapshot?
    private var panelOpen = false
    private var battery: BatterySnapshot?
    private var watcher: ShownWatcher?

    public convenience init(_ ctx: AppContext) {
        self.init(ctx, readBattery: { BatteryReader.read(fresh: $0) })
    }

    init(_ ctx: AppContext, readBattery: @escaping (_ fresh: Bool) -> BatterySnapshot?) {
        self.ctx = ctx
        self.readBattery = readBattery
        watcher = ShownWatcher(settings: ctx.settings, id: .overview) { [weak self] in self?.model.clearSparks() }
    }

    private var settings: AppSettings { ctx.settings }

    public var label: AnyView { AnyView(OverviewLabel(model: model)) }

    public var panel: AnyView {
        AnyView(OverviewLivePanel(model: model, settings: settings).refreshing(every: .seconds(3)) { [weak self] in
            await self?.refreshPanel()
        })
    }

    /// The scheduler ticks items in registration order and Overview registers last, so the sources in the menu bar
    /// have already ticked this beat. The rest are ticked here; a source out of the menu bar otherwise never updates.
    public func tick(now: Date) {
        feed(Self.glyphSources + (panelOpen ? Self.panelSources : []), now: now)
        collect(now: now)
        model.recordSparks(OverviewStyle.list.metrics.filter(isFresh))
    }

    public func panelDidOpen() {
        panelOpen = true
        // CPU's process baseline belongs to whichever panel shows the rows; start it fresh, as the CPU panel does.
        if let cpu = ctx.scheduler.item(.cpu) { ctx.panels.opened(cpu) }
        // The glyph sources ticked moments ago; a second tick now would measure a sliver of a second.
        feed(Self.panelSources, now: .now)
        collect(now: .now, freshBattery: true)
    }

    public func panelDidClose() {
        panelOpen = false
        model.topProcesses = nil
        if let cpu = ctx.scheduler.item(.cpu) { ctx.panels.closed(cpu) }
    }

    /// Every three seconds while the panel is open. Only the List style's open CPU row has rows to sample.
    func refreshPanel() async {
        guard settings.overviewStyle == .list, model.expanded.contains(.cpu),
              let cpu = ctx.scheduler.item(.cpu) as? CPUItem else {
            if model.topProcesses != nil { model.topProcesses = nil }
            return
        }
        await cpu.refreshTop()
        guard !Task.isCancelled, panelOpen else { return }
        model.topProcesses = cpu.model.topProcesses
    }

    private func feed(_ ids: [ItemID], now: Date) {
        for id in ids where !settings.isInMenuBar(id) {
            ctx.scheduler.item(id)?.tick(now: now)
        }
    }

    /// Whether a row's figure was read this beat, so its sparkline only gets real samples.
    private func isFresh(_ metric: OverviewMetric) -> Bool {
        switch metric {
        case .cpu, .gpu, .memory: true
        case .cpuTemp, .gpuTemp, .batteryTemp, .hottest: panelOpen || settings.isInMenuBar(.temps)
        case .network: panelOpen || settings.isInMenuBar(.network)
        case .disk: panelOpen || settings.isInMenuBar(.disk)
        case .battery, .systemPower: readsBattery
        }
    }

    /// Battery and Power share one reading per beat, so while either is in the menu bar this costs nothing.
    private var readsBattery: Bool {
        panelOpen || settings.isInMenuBar(.battery) || settings.isInMenuBar(.power)
    }

    private func collect(now: Date, freshBattery: Bool = false) {
        if readsBattery { battery = readBattery(freshBattery) }
        let cpu = ctx.scheduler.item(.cpu) as? CPUItem
        var r = OverviewReading()
        r.cpu = cpu?.model.total
        r.gpu = (ctx.scheduler.item(.gpu) as? GPUItem)?.model.utilization
        r.memory = (ctx.scheduler.item(.memory) as? MemoryItem)?.model.stats
        r.temps = (ctx.scheduler.item(.temps) as? TempsItem)?.summary ?? TempSummary()
        r.network = (ctx.scheduler.item(.network) as? NetworkItem)?.rate.map { NetworkRate(up: $0.up, down: $0.down) }
        r.disk = (ctx.scheduler.item(.disk) as? DiskItem)?.capacity
        r.battery = battery
        r.systemWatts = battery?.systemLoadW
        r.temperatureUnit = settings.temperatureUnit
        r.networkUnit = settings.networkUnit
        model.update(r)
        // The cores chart only shows in the List style's open CPU row.
        if panelOpen, let cores = cpu?.model.cores { model.cores = cores }
    }

    public func renderVariants() async -> [RenderVariant] {
        // `--render` has ticked every item already; this only copies their readings.
        collect(now: .now, freshBattery: true)
        if let cores = (ctx.scheduler.item(.cpu) as? CPUItem)?.model.cores { model.cores = cores }
        let sample = Self.sampleModel()
        let sampleLabel = AnyView(OverviewLabel(model: sample))
        var variants = [RenderVariant("live", label: label, panel: AnyView(OverviewLivePanel(model: model, settings: settings)))]
        for style in OverviewStyle.allCases {
            variants.append(RenderVariant("sample-\(style.rawValue)", label: sampleLabel,
                                          panel: AnyView(OverviewPanel(model: sample, style: style))))
        }
        // A reordered panel: Bars with its groups split goes flat; Tiles keeps Network full width mid-grid.
        let barsOrder: [OverviewMetric] = [.network, .cpu, .cpuTemp, .gpu, .gpuTemp, .memory, .battery, .systemPower]
        variants.append(RenderVariant("sample-bars-reordered", label: sampleLabel,
                                      panel: AnyView(OverviewPanel(model: sample, style: .bars, metrics: barsOrder))))
        let tilesOrder: [OverviewMetric] = [.cpu, .gpu, .network, .memory, .hottest, .battery]
        variants.append(RenderVariant("sample-tiles-reordered", label: sampleLabel,
                                      panel: AnyView(OverviewPanel(model: sample, style: .tiles, metrics: tilesOrder))))
        return variants
    }

    /// The README's sample figures, matching the condensed mockups.
    static func sampleModel() -> OverviewModel {
        var r = OverviewReading()
        r.cpu = 29
        r.gpu = 100
        let gib = UInt64(1 << 30)
        r.memory = MemoryStats(usedBytes: UInt64(7.8 * Double(gib)), totalBytes: 16 * gib, usedPercent: 49)
        r.temps = TempSummary(cpu: 58, gpu: 54, battery: 35, hottest: 72, cpuHottest: 66)
        var battery = BatterySnapshot()
        battery.percent = 34
        battery.onAC = true
        battery.isCharging = true
        battery.minutesToFull = 114
        battery.systemLoadW = 18.2
        battery.temperatureC = 35
        r.battery = battery
        r.systemWatts = battery.systemLoadW
        r.network = NetworkRate(up: 89_000, down: 95_000)
        r.disk = DiskCapacity(name: "Macintosh HD", available: 412_000_000_000, total: 981_000_000_000)
        let model = OverviewModel(reading: r)
        let loads: [Double] = [60, 52, 44, 38, 34, 26, 18, 12, 6, 0]
        model.cores = loads.enumerated().map {
            CoreLoad(id: $0.offset, percent: $0.element, kind: $0.offset < 4 ? .efficiency : .performance)
        }
        model.topProcesses = [
            ProcessRow(id: 1, name: "Safari", icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"), percent: 12),
            ProcessRow(id: 2, name: "WindowServer", icon: NSWorkspace.shared.icon(for: .applicationBundle), percent: 6),
        ]
        let sparks: [OverviewMetric: [Double]] = [
            .cpu: [24, 28, 36, 31, 26, 30, 33, 29], .gpu: [60, 80, 95, 100, 90, 100, 100, 100],
            .memory: [46, 47, 47, 48, 48, 49, 49, 49], .hottest: [64, 66, 69, 71, 70, 72, 71, 72],
            .battery: [24, 26, 27, 29, 30, 31, 33, 34], .network: [40, 90, 60, 120, 80, 95, 70, 95],
            .disk: [5, 5, 5, 5, 5, 5, 5, 5],
        ]
        for (row, values) in sparks { model.setSparks(row, values) }
        return model
    }
}

public extension OverviewItem {
    /// The Overview item in a menu bar strip at the sample figures for `--render`: beside the other items, and alone,
    /// as it is with Hide Other Items on.
    static func renderStrips() -> [(name: String, view: AnyView)] {
        let glyph = OverviewLabel(model: sampleModel())
        let beside = HStack(spacing: 12) {
            glyph
            StackedLabel(caption: "CPU", value: "29%", widest: "100%")
            StackedLabel(caption: "GPU", value: "100%", widest: "100%")
            StackedLabel(caption: "RAM", value: "49%", widest: "100%")
            StackedLabel(caption: "TEMP", value: "72°C", widest: "100°C")
            StackedLabel(top: "↑ 89K", bottom: "↓ 95K", widest: "↓ 999M")
            StackedLabel(caption: "SSD", value: "412G", widest: "999G")
            StackedLabel(caption: "POWER", value: "18W", widest: "188W")
            let battery = BatteryIcon.label(percent: 34, glyph: .bolt, showPercentage: true)
            Image(nsImage: battery).renderingMode(.template).frame(width: battery.size.width, height: battery.size.height)
        }
        .fixedSize()
        return [("beside", AnyView(beside)), ("replacing", AnyView(glyph))]
    }
}
