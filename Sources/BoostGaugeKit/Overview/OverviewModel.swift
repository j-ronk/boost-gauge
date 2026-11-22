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

/// The rows of the List style, top to bottom.
enum OverviewRow: String, CaseIterable, Sendable {
    case cpu, gpu, memory, temps, battery, network, disk

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .temps: "Temperatures"
        case .battery: "Battery"
        case .network: "Network"
        case .disk: "Disk"
        }
    }

    /// The value the row's sparkline follows.
    func sparkValue(_ r: OverviewReading) -> Double? {
        switch self {
        case .cpu: r.cpu
        case .gpu: r.gpu
        case .memory: r.memory?.usedPercent
        case .temps: r.temps.hottest
        case .battery: r.battery.map { Double($0.percent) }
        case .network: r.network?.down
        case .disk: r.disk.flatMap(OverviewText.diskUsedPercent)
        }
    }
}

@MainActor @Observable final class OverviewModel {
    /// About 40 s at the default refresh: enough for a shape, short enough to read as "now".
    static let sparkLength = 20

    private(set) var reading = OverviewReading()
    /// The menu bar glyph's bar heights. Kept apart from `reading` so the label only redraws when a bar moves.
    private(set) var glyph = OverviewGlyph.heights(cpu: nil, gpu: nil, memory: nil)
    private(set) var sparks: [OverviewRow: [Double]] = [:]
    var cores: [CoreLoad] = []
    var topProcesses: [ProcessRow]?
    /// Which List rows are open. Remembered while the app runs; CPU starts open.
    var expanded: Set<OverviewRow> = [.cpu]

    init(reading: OverviewReading = OverviewReading()) {
        update(reading)
    }

    /// Observable notifies on every write, equal or not, so unchanged values aren't written back.
    func update(_ next: OverviewReading) {
        if next != reading { reading = next }
        let heights = OverviewGlyph.heights(cpu: next.cpu, gpu: next.gpu, memory: next.memory?.usedPercent)
        if heights != glyph { glyph = heights }
    }

    /// Adds the current value of each row in `rows` to its sparkline.
    func recordSparks(_ rows: [OverviewRow]) {
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

    func setSparks(_ row: OverviewRow, _ values: [Double]) {
        sparks[row] = Array(values.suffix(Self.sparkLength))
    }

    func toggle(_ row: OverviewRow) {
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

    /// The List row's value at the right.
    static func rowValue(_ row: OverviewRow, _ r: OverviewReading) -> String {
        switch row {
        case .cpu: percent(r.cpu)
        case .gpu: percent(r.gpu)
        case .memory: percent(r.memory?.usedPercent)
        case .temps: temperature(r.temps.hottest, r.temperatureUnit)
        case .battery: batteryPercent(r.battery)
        case .network: r.network.map { NetworkCounters.rateText($0.down, unit: r.networkUnit) } ?? "—"
        case .disk: diskFree(r.disk)
        }
    }
}
