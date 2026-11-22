import AppKit
import IOKit
import IOKit.ps
import Observation
import SwiftUI

/// Reads the live battery in-process. Battery and Power tick on the same scheduler beat,
/// so a reading taken moments ago is shared instead of hitting IOKit twice.
@MainActor enum BatteryReader {
    private static var last: (date: Date, withPack: Bool, snapshot: BatterySnapshot)?

    // Only what the parser uses: the full AppleSmartBattery dictionary drags in tens of KB of IOReport legends.
    private static let smartBatteryKeys = [
        "CurrentCapacity", "ExternalConnected", "IsCharging", "FullyCharged", "Voltage", "InstantAmperage", "Amperage",
        "CycleCount", "PowerTelemetryData", "AdapterDetails", "BatteryData", "ChargerData", "ChargerInhibitReason",
    ]

    /// `fresh` skips the shared reading, for events (plug, panel open) that may have just changed it.
    static func read(includePack: Bool, now: Date = .now, fresh: Bool = false) -> BatterySnapshot? {
        if !fresh, let last, now.timeIntervalSince(last.date) < 0.5, last.withPack || !includePack { return last.snapshot }
        guard let iops = powerSource() else { return nil }
        let smartBattery = properties(ofClass: "AppleSmartBattery", keys: smartBatteryKeys)
        let pack = includePack ? properties(ofClass: "AppleSmartBatteryPack", keys: ["BatteryData"]) : nil
        let snapshot = BatteryParser.parse(iops: iops, smartBattery: smartBattery, pack: pack)
        last = (now, includePack, snapshot)
        return snapshot
    }

    private static func powerSource() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            return d
        }
        return nil
    }

    private static func properties(ofClass name: String, keys: [String]) -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
        guard service != IO_OBJECT_NULL else { return [:] }
        defer { IOObjectRelease(service) }
        var result: [String: Any] = [:]
        for key in keys {
            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                result[key] = value
            }
        }
        return result
    }
}

struct LabelContent: Equatable {
    let percent: Int
    let glyph: BatteryGlyph
    var lowPower = false
}

struct EnergyUser: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let impact: Double
}

/// What the battery panel and label draw. Live, it's fed by `BatteryItem`; for `--render`, by fixed samples.
@MainActor @Observable final class BatteryModel {
    var snapshot: BatterySnapshot? {
        didSet { updateLabelContent() }
    }
    /// Low Power Mode, which turns the menu bar charge yellow.
    var lowPower = false {
        didSet { updateLabelContent() }
    }
    private(set) var labelContent: LabelContent?
    var users: [EnergyUser] = []
    var usersLoaded = false
    var systemHealthPercent: Int?
    var fans: [FanReading] = []
    var powerHistory = PowerHistory()
    var historyRange: HistoryRange = .day {
        didSet { reloadHistory() }
    }
    private(set) var historySegments: [[ChargeSample]] = []
    private(set) var historyNow: Date

    @ObservationIgnored let history: HistoryStore?
    @ObservationIgnored private let fixedHistory: [ChargeSample]
    @ObservationIgnored var refreshUsers: (() async -> Void)?

    init(history: HistoryStore?, fixedHistory: [ChargeSample] = [], now: Date = .now) {
        self.history = history
        self.fixedHistory = fixedHistory
        historyNow = now
        reloadHistory(now: now)
    }

    var state: ChargeState? { snapshot.map(ChargeState.classify) }

    /// Amperage moves every tick; the menu bar icon should only redraw when what it shows changes.
    private func updateLabelContent() {
        let icon = snapshot.map {
            LabelContent(percent: $0.percent, glyph: BatteryIcon.glyph(for: ChargeState.classify($0)), lowPower: lowPower)
        }
        if icon != labelContent { labelContent = icon }
    }

    var healthPercent: Int? { systemHealthPercent ?? snapshot?.healthPercent }

    func reloadHistory(now: Date = .now) {
        historyNow = now
        // Render samples carry their own history so they never touch the real file.
        historySegments = history?.series(historyRange, now: now)
            ?? HistoryStore.series(of: fixedHistory, historyRange, now: now)
    }
}

/// The battery menu bar item: the system-style battery icon, and the panel with charge, Energy Mode, history,
/// power, health and the apps using energy.
@MainActor public final class BatteryItem: BoostGaugeItem {
    public let id = ItemID.battery
    private let ctx: AppContext
    let model: BatteryModel
    private let store: HistoryStore
    private var panelOpen = false
    private let readFans: () -> [FanReading]
    private var historyTask: Task<Void, Never>?
    private var identities: [pid_t: (key: String, name: String)] = [:]
    private var icons: [String: NSImage] = [:]
    private var healthFetched: Date?
    private var healthFetching = false
    private let lowPower: LowPowerMonitor

    public convenience init(_ ctx: AppContext) {
        // --render must not write the real history file.
        let source = FanSource()
        self.init(ctx, historyURL: HistoryStore.defaultURL, recordsHistory: !CommandLine.arguments.contains("--render"),
                  readFans: { source.read() })
    }

    init(_ ctx: AppContext, historyURL: URL, recordsHistory: Bool, readFans: @escaping () -> [FanReading] = { [] },
         lowPower: LowPowerMonitor? = nil) {
        self.ctx = ctx
        self.readFans = readFans
        self.lowPower = lowPower ?? LowPowerMonitor()
        store = HistoryStore(url: historyURL)
        model = BatteryModel(history: store)
        model.refreshUsers = { [weak self] in await self?.refreshUsers() }
        if recordsHistory { startHistory() }
        watchPowerSource()
        watchLowPower()
    }

    deinit { historyTask?.cancel() }

    public var label: AnyView { AnyView(BatteryLabel(model: model, settings: ctx.settings)) }
    public var panel: AnyView { AnyView(BatteryPanel(model: model, ctx: ctx)) }

    public func tick(now: Date) {
        read(now: now, fresh: false)
        lowPower.refresh()
        if panelOpen { model.fans = readFans() }
    }

    private func read(now: Date, fresh: Bool) {
        if let s = BatteryReader.read(includePack: panelOpen, now: now, fresh: fresh) {
            model.snapshot = s
            model.powerHistory.add(s, at: now)
        }
    }

    public func panelDidOpen() {
        panelOpen = true
        read(now: .now, fresh: true)
        model.fans = readFans()
        model.reloadHistory()
        refreshHealth()
    }

    public func panelDidClose() {
        panelOpen = false
        model.fans = []
    }

    /// Apple's figure moves at most daily, so an hourly 0.1 s system_profiler run while the panel is open is plenty.
    private func refreshHealth() {
        if healthFetching { return }
        if let healthFetched, Date.now.timeIntervalSince(healthFetched) < 3600 { return }
        healthFetching = true
        Task { [weak self] in
            let (status, out) = await Shell.run("/usr/sbin/system_profiler", ["SPPowerDataType"])
            guard let self else { return }
            self.healthFetching = false
            guard status == 0, let percent = BatteryParser.maximumCapacityPercent(systemProfiler: out) else { return }
            self.healthFetched = .now
            self.model.systemHealthPercent = percent
        }
    }

    // MARK: History

    private func startHistory() {
        let firstLaunch = !store.fileExists
        store.compact(now: .now)
        historyTask = Task { [weak self] in
            if firstLaunch { await self?.seedFromPmset() }
            var appended = 0
            while !Task.isCancelled {
                guard let self else { return }
                self.recordSample(now: .now)
                appended += 1
                // Trimming rewrites the file, so do it a few times a day rather than every minute.
                if appended % 360 == 0 { self.store.compact(now: .now) }
                try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
            }
        }
    }

    private func recordSample(now: Date) {
        guard let s = BatteryReader.read(includePack: false, now: now) else { return }
        var charging = false
        if case .charging = ChargeState.classify(s) { charging = true }
        store.append(ChargeSample(date: now, percent: s.percent, charging: charging))
        if panelOpen { model.reloadHistory(now: now) }
    }

    /// First launch only: `pmset -g log` gives a few days of history so the chart doesn't open empty.
    private func seedFromPmset() async {
        let (status, out) = await Shell.run("/usr/bin/pmset", ["-g", "log"])
        guard status == 0 else { return }
        let samples = await Task.detached(priority: .utility) { PmsetLogParser.chargeSamples(out) }.value
        let cutoff = Date.now.addingTimeInterval(-HistoryStore.keep)
        store.seed(samples.filter { $0.date >= cutoff })
        model.reloadHistory()
    }

    // MARK: Power source

    /// A plug or unplug updates the icon now instead of on the next tick.
    private func watchPowerSource() {
        withObservationTracking {
            _ = ctx.powerSource.current
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.ctx.settings.isShown(.battery) { self.read(now: .now, fresh: true) }
                self.watchPowerSource()
            }
        }
    }

    private func watchLowPower() {
        model.lowPower = withObservationTracking {
            lowPower.isOn
        } onChange: { [weak self] in
            // onChange fires before the new value is stored; hop so the read sees it.
            Task { @MainActor in self?.watchLowPower() }
        }
    }

    // MARK: Using Energy

    private func refreshUsers() async {
        let (status, out) = await Shell.run("/usr/bin/top", ["-l", "2", "-s", "1", "-stats", "pid,command,power", "-o", "power", "-n", "30"])
        guard status == 0 else { return }
        let rows = await Task.detached(priority: .utility) { EnergyUsers.parseTop(out) }.value
        let live = Set(rows.map(\.pid))
        identities = identities.filter { live.contains($0.key) }
        let top = EnergyUsers.rollup(rows) { pid in identify(pid) }
        model.users = top.map { EnergyUser(id: $0.key, name: $0.name, icon: icons[$0.key] ?? NSImage(), impact: $0.power) }
        model.usersLoaded = true
    }

    private func identify(_ pid: pid_t) -> (key: String, name: String) {
        if let known = identities[pid] { return known }
        let who = AppIdentity.resolve(pid: pid)
        identities[pid] = (who.key, who.name)
        if icons[who.key] == nil { icons[who.key] = who.icon }
        return (who.key, who.name)
    }

    // MARK: Render

    public func renderVariants() async -> [RenderVariant] {
        var variants = [RenderVariant("live", label: label, panel: panel)]
        for sample in BatterySamples.all {
            let m = BatterySamples.model(sample)
            variants.append(RenderVariant(sample.name, label: AnyView(BatteryLabel(model: m, settings: ctx.settings)),
                                          panel: AnyView(BatteryPanel(model: m, ctx: ctx))))
        }
        variants.append(RenderVariant("levels", label: AnyView(BatterySamples.LevelStrip()), panel: nil))
        variants.append(RenderVariant("levels-no-percent", label: AnyView(BatterySamples.LevelStrip(showPercentage: false)), panel: nil))
        variants.append(RenderVariant("levels-glyph-only", label: AnyView(BatterySamples.LevelStrip(style: .glyphOnly)), panel: nil))
        variants.append(RenderVariant("levels-low-power", label: AnyView(BatterySamples.LevelStrip(lowPower: true)), panel: nil))
        variants.append(RenderVariant("levels-low-power-no-percent",
                                      label: AnyView(BatterySamples.LevelStrip(showPercentage: false, lowPower: true)), panel: nil))
        variants.append(RenderVariant("sf-symbols", label: AnyView(BatterySamples.SFSymbolStrip()), panel: nil))
        return variants
    }
}
