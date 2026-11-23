import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct CoreLoad: Identifiable {
    let id: Int
    let percent: Double
    let kind: CoreKind
}

struct ProcessRow: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage
    let percent: Double
}

@MainActor @Observable final class CPUModel {
    var total: Double?
    var cores: [CoreLoad] = []
    var topProcesses: [ProcessRow]?
    var temperature: Double?
    var hottestSensor: Double?
    var temperatureUnit = TemperatureUnit.celsius
    var efficiencyCores = 0
    var performanceCores = 0
    var logicalCores = ProcessInfo.processInfo.activeProcessorCount

    var labelValue: String { total.map(Format.percent) ?? "—" }
    var temperatureText: String { temperature.map { SensorSummary.format($0, temperatureUnit) } ?? "—" }
    var hottestSensorText: String { hottestSensor.map { SensorSummary.format($0, temperatureUnit) } ?? "—" }
    var coresText: String { CPUCores.text(efficiency: efficiencyCores, performance: performanceCores, logical: logicalCores) }
}

enum CPUCores {
    /// "4 Efficiency · 6 Performance"; a Mac without the perflevel split (Intel) shows its plain core count.
    static func text(efficiency: Int, performance: Int, logical: Int = 0) -> String {
        if efficiency > 0, performance > 0 { return "\(efficiency) Efficiency · \(performance) Performance" }
        let total = efficiency + performance > 0 ? efficiency + performance : logical
        return total > 0 ? "\(total)" : "—"
    }
}

@MainActor public final class CPUItem: BoostGaugeItem {
    public let id = ItemID.cpu
    let model = CPUModel()

    private let settings: AppSettings
    private let charts: ChartHistory
    private let readTicks: () -> [CoreTicks]?
    private let readTemperatures: () -> TempSummary
    private let kinds: [CoreKind]
    private let settleDelay: Duration?
    private var previous: [CoreTicks]?
    private var lastSample: Date?
    private var settleTask: Task<Void, Never>?
    private var watcher: ShownWatcher?
    private var processBaseline: (snapshot: [ProcessCPUTime], at: ContinuousClock.Instant)?

    public convenience init(_ ctx: AppContext) {
        // Created on the first panel open; key discovery probes the SMC about 100 times.
        var temperatures: TemperatureReader?
        self.init(ctx, readTicks: CPUTicks.read, readTemperatures: {
            let reader = temperatures ?? TemperatureReader(smc: SMC())
            temperatures = reader
            return SensorSummary.summarize(reader.read())
        }, kinds: CPULoad.coreKindsOfThisMac(), settleDelay: .milliseconds(500))
    }

    /// `settleDelay`: after a fresh baseline, take the second read this soon instead of a whole interval later,
    /// so the label isn't "—" for seconds after launch or re-show.
    init(_ ctx: AppContext, readTicks: @escaping () -> [CoreTicks]?,
         readTemperatures: @escaping () -> TempSummary = { TempSummary() },
         kinds: [CoreKind] = [], settleDelay: Duration? = nil) {
        settings = ctx.settings
        charts = ctx.charts
        self.readTicks = readTicks
        self.readTemperatures = readTemperatures
        self.kinds = kinds
        self.settleDelay = settleDelay
        model.efficiencyCores = kinds.filter { $0 == .efficiency }.count
        model.performanceCores = kinds.filter { $0 == .performance }.count
        watcher = ShownWatcher(settings: ctx.settings, id: .cpu) { [weak self] in self?.resetBaseline() }
    }

    public var label: AnyView {
        let model = model
        return AnyView(PercentLabel(caption: "CPU") { model.labelValue })
    }

    public var panel: AnyView {
        AnyView(CPUPanel(model: model, settings: settings, charts: charts).refreshing(every: .seconds(3)) { [weak self] in
            self?.refreshDetails()
            await self?.refreshTop()
        })
    }

    /// Temperatures are read only while the panel is open, like the GPU panel's.
    func refreshDetails() {
        guard settings.isSectionShown(.cpuDetails) else {
            // Re-shown, the section must not flash readings from before it was hidden.
            if model.temperature != nil { model.temperature = nil }
            if model.hottestSensor != nil { model.hottestSensor = nil }
            return
        }
        // Observable notifies on every write, equal or not; skip no-op writes so the panel doesn't redraw.
        if model.temperatureUnit != settings.temperatureUnit { model.temperatureUnit = settings.temperatureUnit }
        let summary = readTemperatures()
        if model.temperature != summary.cpu { model.temperature = summary.cpu }
        if model.hottestSensor != summary.cpuHottest { model.hottestSensor = summary.cpuHottest }
    }

    public func tick(now: Date) {
        // Ticks stop during sleep, and a hide/re-show within one main-actor turn never reaches ShownWatcher.
        // Either way a delta over the gap is meaningless, so start over.
        if let lastSample, now.timeIntervalSince(lastSample) > Double(3 * settings.refreshSeconds + 1) {
            resetBaseline()
        }
        lastSample = now
        let hadBaseline = previous != nil
        sample(now: now)
        guard !hadBaseline, previous != nil, let settleDelay else { return }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled, let self, self.model.total == nil, self.previous != nil else { return }
            self.sample(now: .now)
        }
    }

    public func panelDidOpen() {
        // An in-flight refresh can land after panelDidClose; don't flash its rows on the next open.
        processBaseline = nil
        model.topProcesses = nil
    }

    public func panelDidClose() {
        // Panel-only state: the next open starts a fresh baseline instead of averaging over the closed time.
        processBaseline = nil
        model.topProcesses = nil
    }

    public func renderVariants() async -> [RenderVariant] {
        refreshDetails()
        await refreshTop()
        return [RenderVariant("live", label: label, panel: panel)]
            + RenderVariant.eachRange("sample", label: AnyView(StackedLabel(caption: "CPU", value: "23%", widest: "100%")),
                                      panel: CPUPanel(model: Self.sampleModel(), settings: settings, charts: ChartSamples.history))
            + [
            RenderVariant("low", label: AnyView(StackedLabel(caption: "CPU", value: "7%", widest: "100%")), panel: nil),
            RenderVariant("full", label: AnyView(StackedLabel(caption: "CPU", value: "100%", widest: "100%")), panel: nil),
        ]
    }

    /// A 4E/6P Mac at light load, for `--render`.
    static func sampleModel() -> CPUModel {
        let m = CPUModel()
        m.total = 23
        let loads: [Double] = [52, 44, 36, 30, 26, 18, 12, 8, 4, 1]
        m.cores = loads.enumerated().map { CoreLoad(id: $0.offset, percent: $0.element, kind: $0.offset < 4 ? .efficiency : .performance) }
        m.efficiencyCores = 4
        m.performanceCores = 6
        m.temperature = 58.4
        m.hottestSensor = 66.2
        m.topProcesses = [
            ProcessRow(id: 1, name: "Safari", icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"), percent: 12),
            ProcessRow(id: 2, name: "WindowServer", icon: NSWorkspace.shared.icon(for: .applicationBundle), percent: 6),
            ProcessRow(id: 3, name: "Mail", icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Mail.app"), percent: 3),
        ]
        return m
    }

    private func sample(now: Date) {
        guard let current = readTicks() else { return }
        if let previous, previous.count == current.count {
            let usage = CPULoad.usage(previous: previous, current: current)
            model.total = usage.total
            charts.record(.cpu, usage.total, at: now)
            model.cores = usage.perCore.enumerated().map { i, percent in
                CoreLoad(id: i, percent: percent, kind: i < kinds.count ? kinds[i] : .performance)
            }
        }
        previous = current
    }

    private func resetBaseline() {
        settleTask?.cancel()
        settleTask = nil
        previous = nil
        model.total = nil
        model.cores = []
    }

    func refreshTop() async {
        // Sampling every process is the panel's dearest read; skip it while nobody can see the rows.
        guard settings.isSectionShown(.cpuTopProcesses) else {
            processBaseline = nil
            if model.topProcesses != nil { model.topProcesses = nil }
            return
        }
        let baseline: (snapshot: [ProcessCPUTime], at: ContinuousClock.Instant)
        if let processBaseline {
            baseline = processBaseline
        } else {
            baseline = (await Self.snapshotOffMain(), .now)
            // A short first window gets rows on screen at once rather than after a full refresh.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
        }
        let current = await Self.snapshotOffMain()
        let now = ContinuousClock.Instant.now
        guard !Task.isCancelled else { return }
        let elapsed = baseline.at.duration(to: now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let top = ProcessSampler.top(previous: baseline.snapshot, current: current, elapsed: seconds, n: 3)
        processBaseline = (current, now)
        model.topProcesses = top.map { row in
            let who = AppIdentity.resolve(pid: row.pid)
            // No rollup here, so a helper keeps its own name (with its app's icon); an app's main process gets the app's name.
            let path = ProcessSampler.executablePath(row.pid)
            let isAppMain = AppIdentity.outermostAppPath(executablePath: path).map { path.hasPrefix($0 + "/Contents/MacOS/") } ?? false
            return ProcessRow(id: row.pid, name: isAppMain ? who.name : AppIdentity.displayName(processName: row.name, executablePath: path), icon: who.icon, percent: row.percent)
        }
    }

    private nonisolated static func snapshotOffMain() async -> [ProcessCPUTime] {
        await Task.detached(priority: .utility) { ProcessSampler.snapshot() }.value
    }
}
