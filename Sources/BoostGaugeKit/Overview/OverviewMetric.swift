import Foundation

/// One figure the Overview panel can show. Raw values are stored, so never rename one.
/// Declaration order is the default order, top to bottom: the Bars mockup's.
public enum OverviewMetric: String, CaseIterable, Sendable {
    case cpu, gpu, memory, disk, cpuTemp, gpuTemp, batteryTemp, hottest, battery, systemPower, network

    /// Bars' section for the metric. Bars keeps the headings while each group's metrics stay together.
    enum Group: CaseIterable { case usage, temperatures, power }

    var group: Group {
        switch self {
        case .cpu, .gpu, .memory, .disk: .usage
        case .cpuTemp, .gpuTemp, .batteryTemp, .hottest: .temperatures
        case .battery, .systemPower, .network: .power
        }
    }

    /// The name in Settings and in the panel's rows.
    func title(in style: OverviewStyle) -> String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .cpuTemp: "CPU Temperature"
        case .gpuTemp: "GPU Temperature"
        case .batteryTemp: "Battery Temperature"
        // The List's one temperature row follows the hottest sensor.
        case .hottest: style == .list ? "Temperatures" : "Hottest"
        case .battery: "Battery"
        case .systemPower: "System Power"
        case .network: "Network"
        }
    }

    /// The value the List row's sparkline follows.
    func sparkValue(_ r: OverviewReading) -> Double? {
        switch self {
        case .cpu: r.cpu
        case .gpu: r.gpu
        case .memory: r.memory?.usedPercent
        case .disk: r.disk.flatMap(OverviewText.diskUsedPercent)
        case .cpuTemp: r.temps.cpu
        case .gpuTemp: r.temps.gpu
        case .batteryTemp: r.temps.battery ?? r.battery?.temperatureC
        case .hottest: r.temps.hottest
        case .battery: r.battery.map { Double($0.percent) }
        case .systemPower: r.systemWatts
        case .network: r.network?.down
        }
    }
}

public extension OverviewStyle {
    /// The metrics this style can show, in default order. Bars has a row per sensor; List and Tiles show the hottest
    /// one, as the mockups do.
    var metrics: [OverviewMetric] {
        switch self {
        case .bars: OverviewMetric.allCases.filter { $0 != .hottest }
        case .list, .tiles: [.cpu, .gpu, .memory, .disk, .hottest, .battery, .network]
        }
    }
}

/// The user's top-to-bottom order of Overview metrics, shared by every style.
public enum OverviewOrder {
    /// Drops unknown and repeated metrics, then appends any missing one in declaration order.
    public static func normalized(_ raw: [String]?) -> [OverviewMetric] {
        var seen = Set<OverviewMetric>()
        let known = (raw ?? []).compactMap(OverviewMetric.init(rawValue:)).filter { seen.insert($0).inserted }
        return known + OverviewMetric.allCases.filter { !seen.contains($0) }
    }

    /// Whether Bars can head its rows by group: every group's visible metrics sit together.
    static func isGrouped(_ metrics: [OverviewMetric]) -> Bool {
        var finished = Set<OverviewMetric.Group>()
        var current: OverviewMetric.Group?
        for group in metrics.map(\.group) where group != current {
            if let current { finished.insert(current) }
            if finished.contains(group) { return false }
            current = group
        }
        return true
    }

    /// Bars' sections: one per group run, headed while grouped, otherwise a single untitled run.
    static func sections(_ metrics: [OverviewMetric]) -> [[OverviewMetric]] {
        guard isGrouped(metrics) else { return metrics.isEmpty ? [] : [metrics] }
        var out: [[OverviewMetric]] = []
        for metric in metrics {
            if let last = out.last?.last, last.group == metric.group { out[out.count - 1].append(metric) } else { out.append([metric]) }
        }
        return out
    }

    /// Tiles' rows: pairs, with Network on a row of its own wherever it lands. A tile left without a partner keeps
    /// half the width.
    static func tileRows(_ metrics: [OverviewMetric]) -> [[OverviewMetric]] {
        tileRows(wide: metrics.map { $0 == .network }).map { $0.map { metrics[$0] } }
    }

    /// The same rows as indices, for the layout, which only knows which tiles are wide.
    static func tileRows(wide: [Bool]) -> [[Int]] {
        var rows: [[Int]] = []
        var pending: Int?
        for (i, isWide) in wide.enumerated() {
            if isWide {
                if let p = pending { rows.append([p]); pending = nil }
                rows.append([i])
            } else if let p = pending {
                rows.append([p, i])
                pending = nil
            } else {
                pending = i
            }
        }
        if let pending { rows.append([pending]) }
        return rows
    }
}
