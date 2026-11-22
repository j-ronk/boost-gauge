import AppKit
import Observation
import SwiftUI

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

    var labelValue: String { total.map(Format.percent) ?? "—" }
}

@MainActor public final class CPUItem: BoostGaugeItem {
    public let id = ItemID.cpu
    let model = CPUModel()

    private let settings: AppSettings
    private let readTicks: () -> [CoreTicks]?
    private let kinds: [CoreKind]
    private let settleDelay: Duration?
    private var previous: [CoreTicks]?
    private var lastSample: Date?
    private var settleTask: Task<Void, Never>?
    private var watcher: ShownWatcher?
    private var processBaseline: (snapshot: [ProcessCPUTime], at: ContinuousClock.Instant)?

    public convenience init(_ ctx: AppContext) {
        self.init(ctx, readTicks: CPUTicks.read, kinds: CPULoad.coreKindsOfThisMac(), settleDelay: .milliseconds(500))
    }

    /// `settleDelay`: after a fresh baseline, take the second read this soon instead of a whole interval later,
    /// so the label isn't "—" for seconds after launch or re-show.
    init(_ ctx: AppContext, readTicks: @escaping () -> [CoreTicks]?, kinds: [CoreKind] = [], settleDelay: Duration? = nil) {
        settings = ctx.settings
        self.readTicks = readTicks
        self.kinds = kinds
        self.settleDelay = settleDelay
        watcher = ShownWatcher(settings: ctx.settings, id: .cpu) { [weak self] in self?.resetBaseline() }
    }

    public var label: AnyView {
        let model = model
        return AnyView(PercentLabel(caption: "CPU") { model.labelValue })
    }

    public var panel: AnyView {
        AnyView(CPUPanel(model: model).refreshing(every: .seconds(3)) { [weak self] in await self?.refreshTop() })
    }

    public func tick(now: Date) {
        // Ticks stop during sleep, and a hide/re-show within one main-actor turn never reaches ShownWatcher.
        // Either way a delta over the gap is meaningless, so start over.
        if let lastSample, now.timeIntervalSince(lastSample) > Double(3 * settings.refreshSeconds + 1) {
            resetBaseline()
        }
        lastSample = now
        let hadBaseline = previous != nil
        sample()
        guard !hadBaseline, previous != nil, let settleDelay else { return }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled, let self, self.settings.isShown(.cpu), self.model.total == nil, self.previous != nil else { return }
            self.sample()
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
        await refreshTop()
        return [
            RenderVariant("live", label: label, panel: panel),
            RenderVariant("low", label: AnyView(StackedLabel(caption: "CPU", value: "7%", widest: "100%")), panel: nil),
            RenderVariant("full", label: AnyView(StackedLabel(caption: "CPU", value: "100%", widest: "100%")), panel: nil),
        ]
    }

    private func sample() {
        guard let current = readTicks() else { return }
        if let previous, previous.count == current.count {
            let usage = CPULoad.usage(previous: previous, current: current)
            model.total = usage.total
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
