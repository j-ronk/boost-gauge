import Foundation
import Observation
import SwiftUI

@MainActor @Observable public final class TempsItem: BoostGaugeItem {
    public let id: ItemID = .temps
    let ctx: AppContext
    public private(set) var summary = TempSummary()
    public private(set) var fans: [FanReading] = []
    /// The panel's per-sensor groups, read only while it's open.
    public private(set) var groups: [TempGroupReading] = []
    /// False until the panel's first read, so it doesn't flash "Unavailable" as it opens.
    private(set) var hasReadGroups = false
    /// Only groups the user has opened or closed; the rest follow `isExpandedByDefault`.
    private var expansion: [TempGroup: Bool]
    @ObservationIgnored private let readTemperatures: () -> [(name: String, celsius: Double)]
    @ObservationIgnored private let readFans: () -> [FanReading]
    @ObservationIgnored private let readGroups: (Set<TempGroup>) -> [TempGroupReading]
    @ObservationIgnored private var persistsExpansion = true

    static let expansionKey = "temps.groupExpanded"
    /// Groups longer than this start collapsed.
    static let collapseThreshold = 3

    public convenience init(_ ctx: AppContext) {
        let smc = SMC()
        let temperatures = TemperatureReader(smc: smc)
        self.init(ctx, readTemperatures: { temperatures.read() }, readFans: { smc.fans() },
                  readGroups: { temperatures.readGroups($0) })
    }

    init(_ ctx: AppContext, readTemperatures: @escaping () -> [(name: String, celsius: Double)],
         readFans: @escaping () -> [FanReading],
         readGroups: @escaping (Set<TempGroup>) -> [TempGroupReading] = { _ in [] }) {
        self.ctx = ctx
        self.readTemperatures = readTemperatures
        self.readFans = readFans
        self.readGroups = readGroups
        let stored = ctx.settings.defaults.dictionary(forKey: Self.expansionKey) as? [String: Bool] ?? [:]
        expansion = Dictionary(uniqueKeysWithValues: stored.compactMap { k, v in TempGroup(rawValue: k).map { ($0, v) } })
    }

    public var label: AnyView { AnyView(TempsLabel(item: self)) }
    public var panel: AnyView { AnyView(TempsPanel(item: self)) }

    public func tick(now: Date) {
        summary = SensorSummary.summarize(readTemperatures())
    }

    /// Fans and the per-sensor groups only matter with the panel open, so they're read here rather than on the
    /// menu bar tick, and hidden sections aren't read at all.
    func refreshPanel() {
        let fans = ctx.settings.isSectionShown(.tempsFans) ? readFans() : []
        if self.fans != fans { self.fans = fans }
        let shown = Set(TempGroup.allCases.filter { ctx.settings.isSectionShown($0.section) })
        let groups = shown.isEmpty ? [] : readGroups(shown)
        if self.groups != groups { self.groups = groups }
        if !hasReadGroups { hasReadGroups = true }
    }

    /// A one-sensor group is just its row; anything longer can open to show each sensor.
    func isExpandable(_ reading: TempGroupReading) -> Bool { reading.sensors.count > 1 }

    func isExpanded(_ reading: TempGroupReading) -> Bool {
        expansion[reading.group] ?? (reading.sensors.count <= Self.collapseThreshold)
    }

    func toggleExpanded(_ reading: TempGroupReading) {
        expansion[reading.group] = !isExpanded(reading)
        guard persistsExpansion else { return }
        ctx.settings.defaults.set(Dictionary(uniqueKeysWithValues: expansion.map { ($0.rawValue, $1) }),
                                  forKey: Self.expansionKey)
    }

    var labelValue: String {
        summary.hottest.map { SensorSummary.format($0, ctx.settings.temperatureUnit) } ?? "—"
    }

    var labelWidest: String { SensorSummary.widest(ctx.settings.temperatureUnit) }

    func text(_ celsius: Double) -> String {
        SensorSummary.format(celsius, ctx.settings.temperatureUnit)
    }

    public func renderVariants() async -> [RenderVariant] {
        // Read both now, so the live header and rows come from the same moment.
        tick(now: .now)
        refreshPanel()
        // A fanless Mac (MacBook Air) must show no fan rows; this Mac has fans, so that case is staged.
        let fanless = staged(Self.sample.filter { $0.group != .powerManager && $0.group != .airflow },
                             fans: [], expanded: nil)
        func variant(_ name: String, _ item: TempsItem) -> RenderVariant {
            RenderVariant(name, label: item.label, panel: item.panel)
        }
        return [
            variant("live", staged(nil, fans: nil, expanded: nil)),
            variant("live-expanded", staged(nil, fans: nil, expanded: true)),
            // The whole opened list in one image, past the scroll cap.
            RenderVariant("live-expanded-all", label: label,
                          panel: AnyView(TempsPanel(item: staged(nil, fans: nil, expanded: true),
                                                    maxSensorsHeight: .infinity))),
            variant("sample", staged(Self.sample, fans: Self.sampleFans, expanded: nil)),
            variant("sample-expanded", staged(Self.sample, fans: Self.sampleFans, expanded: true)),
            variant("fanless", fanless),
        ]
    }

    /// A copy for `--render` that never writes the stored expansion: nil groups or fans keep this Mac's live
    /// readings, nil `expanded` keeps the defaults.
    private func staged(_ groups: [TempGroupReading]?, fans: [FanReading]?, expanded: Bool?) -> TempsItem {
        let live = self
        let item = TempsItem(ctx, readTemperatures: { [] }, readFans: { fans ?? live.fans },
                             readGroups: { _ in groups ?? live.groups })
        item.persistsExpansion = false
        if let expanded { item.expansion = Dictionary(uniqueKeysWithValues: TempGroup.allCases.map { ($0, expanded) }) }
        item.summary = groups.map(Self.summary(of:)) ?? summary
        item.refreshPanel()
        return item
    }

    /// The menu bar's numbers for a staged group set, so the header agrees with the rows below it.
    private static func summary(of groups: [TempGroupReading]) -> TempSummary {
        func g(_ group: TempGroup) -> TempGroupReading? { groups.first { $0.group == group } }
        let cpuGPUBattery = [g(.cpu), g(.gpu), g(.battery)].compactMap { $0?.hottest?.celsius }
        return TempSummary(cpu: g(.cpu)?.average, gpu: g(.gpu)?.average, battery: g(.battery)?.average,
                           hottest: cpuGPUBattery.max(), cpuHottest: g(.cpu)?.hottest?.celsius)
    }

    /// A realistic M1 Max under light load, matching the README image: hottest 72 °C, CPU 58, GPU 54, battery 35.
    static let sample: [TempGroupReading] = {
        let performance = [61.2, 72.0, 57.4, 63.8, 55.1, 59.6, 54.3, 56.9]
        let efficiency = [48.7, 50.6]
        return [
            TempGroupReading(.cpu, performance.enumerated().map { TempSensor("Performance core \($0 + 1)", $1) }
                + efficiency.enumerated().map { TempSensor("Efficiency core \($0 + 1)", $1) }),
            TempGroupReading(.gpu, [57.2, 53.1, 54.4, 51.3].enumerated().map { TempSensor("GPU \($0 + 1)", $1) }),
            TempGroupReading(.memory, [49.7, 50.8, 47.5, 47.6].enumerated().map { TempSensor("Memory \($0 + 1)", $1) }),
            TempGroupReading(.ssd, [TempSensor("SSD", 38.6)]),
            TempGroupReading(.battery, [TempSensor("Battery 1", 34.8), TempSensor("Battery 2", 35.2),
                                        TempSensor("Gas gauge", 35.0)]),
            TempGroupReading(.powerManager, [44.7, 44.8, 44.5, 44.7, 44.9, 44.4, 44.4, 44.9, 44.6, 44.3, 44.8]
                .enumerated().map { TempSensor("Die sensor \($0 + 1)", $1) }),
            TempGroupReading(.airflow, [TempSensor("Left", 43.7), TempSensor("Right", 43.4)]),
            TempGroupReading(.wireless, [TempSensor("Wi-Fi", 45.2)]),
        ]
    }()

    static let sampleFans = [FanReading(index: 0, rpm: 1505, min: 1200, max: 5700),
                             FanReading(index: 1, rpm: 1644, min: 1200, max: 5700)]
}

struct TempsLabel: View {
    let item: TempsItem

    var body: some View {
        StackedLabel(caption: "TEMP", value: item.labelValue, widest: item.labelWidest)
    }
}
