import Foundation
import Observation

struct NetworkRate: Equatable {
    var up: Double
    var down: Double
}

/// The other items' latest readings, copied once per tick so the Overview panel redraws once per tick.
struct OverviewReading: Equatable {
    var cpu: Double?
    var gpu: Double?
    var memory: MemoryStats?
    var temps = TempSummary()
    var battery: BatterySnapshot?
    var systemWatts: Double?
    var network: NetworkRate?
    var disk: DiskCapacity?
    var temperatureUnit = TemperatureUnit.celsius
    var networkUnit = NetworkUnit.bytes
}

@MainActor @Observable final class OverviewModel {
    /// About 40 s at the default refresh: enough for a shape, short enough to read as "now".
    static let sparkLength = 20

    private(set) var reading = OverviewReading()
    private(set) var sparks: [OverviewMetric: [Double]] = [:]
    var cores: [CoreLoad] = []
    var topProcesses: [ProcessRow]?
    /// Which List rows are open. Remembered while the app runs; CPU starts open.
    var expanded: Set<OverviewMetric> = [.cpu]

    init(reading: OverviewReading = OverviewReading()) {
        update(reading)
    }

    /// Observable notifies on every write, equal or not, so unchanged values aren't written back.
    func update(_ next: OverviewReading) {
        if next != reading { reading = next }
    }

    /// Adds the current value of each metric in `rows` to its sparkline.
    func recordSparks(_ rows: [OverviewMetric]) {
        var next = sparks
        for row in rows {
            guard let value = row.sparkValue(reading), value.isFinite else { continue }
            next[row, default: []].append(value)
            if next[row]!.count > Self.sparkLength { next[row]!.removeFirst(next[row]!.count - Self.sparkLength) }
        }
        sparks = next
    }

    func clearSparks() {
        if !sparks.isEmpty { sparks = [:] }
    }

    func setSparks(_ row: OverviewMetric, _ values: [Double]) {
        sparks[row] = Array(values.suffix(Self.sparkLength))
    }

    func toggle(_ row: OverviewMetric) {
        if expanded.contains(row) { expanded.remove(row) } else { expanded.insert(row) }
    }
}

/// Every string and level the Overview panel shows, from one reading.
enum OverviewText {
    static func percent(_ v: Double?) -> String { v.map(Format.percent) ?? "—" }

    /// A 0…1 bar length; nil (no reading) draws an empty track.
    static func fraction(_ percent: Double?) -> Double? {
        guard let percent, percent.isFinite else { return nil }
        return min(1, max(0, percent / 100))
    }

    static func memoryUsed(_ m: MemoryStats?) -> String { m.map { MemoryFormat.gigabytes($0.usedBytes) } ?? "—" }

    static func diskUsedPercent(_ d: DiskCapacity) -> Double? {
        guard d.total > 0 else { return nil }
        return Double(d.total - min(d.total, max(0, d.available))) / Double(d.total) * 100
    }

    static func diskUsed(_ d: DiskCapacity?) -> String {
        d.flatMap(diskUsedPercent).map { "\(Format.percent($0)) used" } ?? "—"
    }

    /// "412 GB": the Disk item's figure, spelled out for the panel.
    static func diskFree(_ d: DiskCapacity?) -> String {
        guard let d else { return "—" }
        let compact = DiskStats.freeLabel(d.available)
        return "\(compact.dropLast()) \(compact.last!)B"
    }

    static func temperature(_ celsius: Double?, _ unit: TemperatureUnit) -> String {
        celsius.map { SensorSummary.format($0, unit) } ?? "—"
    }

    /// Temperature bars run from 0 to 100 °C whatever the unit shown.
    static func temperatureFraction(_ celsius: Double?) -> Double? { fraction(celsius) }

    static func batteryPercent(_ b: BatterySnapshot?) -> String { b.map { "\($0.percent)%" } ?? "—" }

    static func batteryStatus(_ b: BatterySnapshot?) -> String? { b.map { ChargeState.classify($0).headerText } }

    /// Whole watts: "18 W".
    static func watts(_ w: Double?) -> String {
        guard let w, w.isFinite else { return "—" }
        return "\(Int(w.rounded())) W"
    }

    static func download(_ r: NetworkRate?, _ unit: NetworkUnit) -> String {
        r.map { "↓ " + NetworkCounters.rateText($0.down, unit: unit) } ?? "↓ —"
    }

    static func upload(_ r: NetworkRate?, _ unit: NetworkUnit) -> String {
        r.map { "↑ " + NetworkCounters.rateText($0.up, unit: unit) } ?? "↑ —"
    }

    /// What a glyph bar stands for, read out by VoiceOver: Disk's bar is how full it is.
    static func glyphValue(_ metric: OverviewMetric, _ r: OverviewReading) -> String {
        metric == .disk ? diskUsed(r.disk) : rowValue(metric, r)
    }

    /// The List row's figure, at the right.
    static func rowValue(_ metric: OverviewMetric, _ r: OverviewReading) -> String {
        switch metric {
        case .cpu: percent(r.cpu)
        case .gpu: percent(r.gpu)
        case .memory: percent(r.memory?.usedPercent)
        case .disk: diskFree(r.disk)
        case .cpuTemp: temperature(r.temps.cpu, r.temperatureUnit)
        case .gpuTemp: temperature(r.temps.gpu, r.temperatureUnit)
        case .batteryTemp: temperature(r.temps.battery ?? r.battery?.temperatureC, r.temperatureUnit)
        case .hottest: temperature(r.temps.hottest, r.temperatureUnit)
        case .battery: batteryPercent(r.battery)
        case .systemPower: watts(r.systemWatts)
        case .network: r.network.map { NetworkCounters.rateText($0.down, unit: r.networkUnit) } ?? "—"
        }
    }
}
