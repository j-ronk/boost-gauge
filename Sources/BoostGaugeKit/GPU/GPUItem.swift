import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct GPUAppRow: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let percent: Double
}

/// What the panel reads on each refresh, off the main thread.
struct GPUPanelReading: Sendable {
    var memoryBytes: UInt64?
    var cores: Int?
    var gpuTime: [pid_t: UInt64] = [:]

    static func read() -> GPUPanelReading {
        let accelerators = GPUReader.readAccelerators(keys: GPUReader.detailKeys)
        return GPUPanelReading(memoryBytes: GPUReader.memoryInUse(accelerators), cores: GPUReader.coreCount(accelerators),
                               gpuTime: GPUClients.gpuTime(GPUClients.read()))
    }
}

@MainActor @Observable final class GPUModel {
    var utilization: Double?
    var memoryBytes: UInt64?
    var temperature: Double?
    var temperatureUnit = TemperatureUnit.celsius
    var cores: Int?
    var topApps: [GPUAppRow]?

    var labelValue: String { utilization.map(Format.percent) ?? "—" }
    var memoryText: String { memoryBytes.map(MemoryFormat.appSize) ?? "—" }
    var temperatureText: String { temperature.map { SensorSummary.format($0, temperatureUnit) } ?? "—" }
    var coresText: String { cores.map(String.init) ?? "—" }
}

@MainActor public final class GPUItem: BoostGaugeItem {
    public let id = ItemID.gpu
    let model = GPUModel()

    private let settings: AppSettings
    private let charts: ChartHistory
    private let read: () -> Double?
    private let readPanel: @Sendable () -> GPUPanelReading
    private let readTemperature: () -> Double?
    private let appKey: @Sendable (pid_t) -> String
    private let resolve: (pid_t) -> (name: String, icon: NSImage)
    private let now: () -> Date
    private let settle: Duration
    private var watcher: ShownWatcher?
    private var baseline: (gpuTime: [pid_t: UInt64], at: Date)?

    public convenience init(_ ctx: AppContext) {
        // Created on the first panel open; key discovery probes the SMC about 100 times.
        var temperatures: TemperatureReader?
        self.init(
            ctx,
            read: { GPUReader.utilization(GPUReader.readAccelerators()) },
            readPanel: { GPUPanelReading.read() },
            readTemperature: {
                let reader = temperatures ?? TemperatureReader(smc: SMC())
                temperatures = reader
                return SensorSummary.summarize(reader.read()).gpu
            },
            appKey: { GPUClients.appKey($0) },
            resolve: { pid in let who = AppIdentity.resolve(pid: pid); return (who.name, who.icon) },
            now: { .now },
            settle: .milliseconds(500)
        )
    }

    /// Everything but `read` runs only from `refreshPanel`, which the open panel drives.
    /// `settle`: the first open takes its second reading this soon, so rows appear at once.
    init(_ ctx: AppContext, read: @escaping () -> Double?,
         readPanel: @escaping @Sendable () -> GPUPanelReading = { GPUPanelReading() },
         readTemperature: @escaping () -> Double? = { nil },
         appKey: @escaping @Sendable (pid_t) -> String = { "\($0)" },
         resolve: @escaping (pid_t) -> (name: String, icon: NSImage) = { ("\($0)", NSImage()) },
         now: @escaping () -> Date = { .now },
         settle: Duration = .zero) {
        settings = ctx.settings
        charts = ctx.charts
        self.read = read
        self.readPanel = readPanel
        self.readTemperature = readTemperature
        self.appKey = appKey
        self.resolve = resolve
        self.now = now
        self.settle = settle
        watcher = ShownWatcher(settings: ctx.settings, id: .gpu) { [weak self] in
            self?.model.utilization = nil
        }
    }

    public var label: AnyView {
        let model = model
        return AnyView(PercentLabel(caption: "GPU") { model.labelValue })
    }

    public var panel: AnyView {
        AnyView(GPUPanel(model: model, settings: settings, charts: charts).refreshing(every: .seconds(3)) { [weak self] in await self?.refreshPanel() })
    }

    public func panelDidOpen() {
        // An in-flight refresh can land after panelDidClose; don't flash its rows on the next open.
        clearPanelState()
    }

    public func panelDidClose() {
        // The next open starts a fresh baseline instead of averaging over the closed time.
        clearPanelState()
    }

    private func clearPanelState() {
        baseline = nil
        if model.topApps != nil { model.topApps = nil }
    }

    func refreshPanel() async {
        // Observable notifies on every write, equal or not; skip no-op writes so the panel doesn't redraw.
        if model.temperatureUnit != settings.temperatureUnit { model.temperatureUnit = settings.temperatureUnit }
        // The SMC read is only for the Details row.
        let temperature = settings.isSectionShown(.gpuDetails) ? readTemperature() : nil
        if model.temperature != temperature { model.temperature = temperature }
        let readPanel = readPanel
        guard settings.isSectionShown(.gpuTopApps) else {
            // No rows to fill: one read for the Details figures, and no per-process sampling or name lookups.
            clearPanelState()
            guard settings.isSectionShown(.gpuDetails) else { return }
            let reading = await Task.detached(priority: .utility) { readPanel() }.value
            guard !Task.isCancelled else { return }
            if model.memoryBytes != reading.memoryBytes { model.memoryBytes = reading.memoryBytes }
            if model.cores != reading.cores { model.cores = reading.cores }
            return
        }
        let start: (gpuTime: [pid_t: UInt64], at: Date)
        if let baseline {
            start = baseline
        } else {
            start = (await Task.detached(priority: .utility) { readPanel() }.value.gpuTime, now())
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled else { return }
        }
        let reading = await Task.detached(priority: .utility) { readPanel() }.value
        let at = now()
        guard !Task.isCancelled else { return }
        baseline = (reading.gpuTime, at)
        if model.memoryBytes != reading.memoryBytes { model.memoryBytes = reading.memoryBytes }
        if model.cores != reading.cores { model.cores = reading.cores }
        let appKey = appKey
        // Keying every busy pid costs a proc_pidpath each, so it stays off the main thread like Memory's rollup.
        let top = await Task.detached(priority: .utility) {
            GPUClients.top(GPUClients.percents(previous: start.gpuTime, current: reading.gpuTime, elapsed: at.timeIntervalSince(start.at)),
                           key: appKey, n: 3)
        }.value
        guard !Task.isCancelled else { return }
        model.topApps = top.map { row in
            let who = resolve(row.pid)
            return GPUAppRow(id: row.key, name: who.name, icon: who.icon, percent: row.percent)
        }
    }

    public func tick(now: Date) {
        let value = read()
        // Observable notifies on every write, equal or not; skip no-op writes so the label and panel don't redraw.
        if model.utilization != value { model.utilization = value }
        charts.record(.gpu, value, at: now)
    }

    public func renderVariants() async -> [RenderVariant] {
        let busy = GPUModel()
        busy.utilization = 100
        busy.memoryBytes = 2_576_980_378
        busy.temperature = 61.4
        busy.cores = 32
        busy.topApps = [
            GPUAppRow(id: "a", name: "Final Cut Pro", icon: NSWorkspace.shared.icon(for: .applicationBundle), percent: 68),
            GPUAppRow(id: "b", name: "WindowServer", icon: NSWorkspace.shared.icon(for: .applicationBundle), percent: 19),
            GPUAppRow(id: "c", name: "Safari", icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"), percent: 6),
        ]
        // Nothing drawing: one dim "None" row.
        let empty = GPUModel()
        empty.topApps = []
        await refreshPanel()
        return [RenderVariant("live", label: label, panel: panel)]
            + RenderVariant.eachRange("sample", label: AnyView(StackedLabel(caption: "GPU", value: "100%", widest: "100%")),
                                      panel: GPUPanel(model: busy, settings: settings, charts: ChartSamples.history))
            + [
            RenderVariant("empty", label: AnyView(StackedLabel(caption: "GPU", value: "—", widest: "100%")),
                          panel: AnyView(GPUPanel(model: empty, settings: settings, charts: ChartHistory()))),
        ]
    }
}
