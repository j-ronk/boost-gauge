import Foundation

public struct TempSummary: Equatable, Sendable {
    public var cpu: Double?
    public var gpu: Double?
    public var battery: Double?
    public var hottest: Double?
    /// The hottest single CPU die sensor, from the same reads as the `cpu` average.
    public var cpuHottest: Double?

    public init(cpu: Double? = nil, gpu: Double? = nil, battery: Double? = nil, hottest: Double? = nil,
                cpuHottest: Double? = nil) {
        self.cpu = cpu
        self.gpu = gpu
        self.battery = battery
        self.hottest = hottest
        self.cpuHottest = cpuHottest
    }
}

public enum SensorGroup: Sendable { case cpu, gpu, battery }

public enum SensorSummary {
    /// CPU and GPU keys are exactly Stats' Apple Silicon tables (M3 mixes CPU and GPU under `Tf`, so no prefix rule
    /// works). Battery cells are `TB<n>T`. There's no SoC group: the only other die sensors are the power manager's
    /// (`TPD..`, HID "PMU tdie"), which run far cooler than the SoC and would mislead.
    public static func group(of name: String) -> SensorGroup? {
        if StatsSensorKeys.cpu.contains(name) { return .cpu }
        if StatsSensorKeys.gpu.contains(name) { return .gpu }
        let u = Array(name.utf8)
        if u.count == 4, u[0] == UInt8(ascii: "T"), u[1] == UInt8(ascii: "B"), (48...57).contains(u[2]),
           u[3] == UInt8(ascii: "T") { return .battery }
        return nil
    }

    /// Group rows are averages, as in Stats; `hottest` is the single hottest grouped sensor (the menu bar value).
    /// Zero, negative and implausibly high readings are dropped: unpopulated keys read 0 and a few glitch high.
    public static func summarize(_ readings: [(name: String, celsius: Double)]) -> TempSummary {
        var groups: [SensorGroup: [Double]] = [:]
        for reading in readings where reading.celsius > 0 && reading.celsius <= 150 {
            guard let group = group(of: reading.name) else { continue }
            groups[group, default: []].append(reading.celsius)
        }
        func average(_ g: SensorGroup) -> Double? {
            guard let values = groups[g], !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        return TempSummary(cpu: average(.cpu), gpu: average(.gpu), battery: average(.battery),
                           hottest: groups.values.flatMap { $0 }.max(), cpuHottest: groups[.cpu]?.max())
    }

    public static func format(_ celsius: Double, _ unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius: "\(Int(celsius.rounded()))°C"
        case .fahrenheit: "\(Int((celsius * 9 / 5 + 32).rounded()))°F"
        }
    }

    public static func widest(_ unit: TemperatureUnit) -> String {
        format(100, unit)
    }

    public static func rpm(_ value: Double, locale: Locale = .current) -> String {
        let rounded = Int(value.rounded())
        return rounded == 0 ? "Off" : "\(rounded.formatted(.number.locale(locale))) rpm"
    }

    /// Every key `group(of:)` knows, probed once to find which this Mac has.
    static let candidateKeys: [String] =
        StatsSensorKeys.cpu.sorted() + StatsSensorKeys.gpu.sorted() + (0...3).map { "TB\($0)T" }
}

/// Reads this Mac's grouped temperature keys. Discovery runs once (about 100 probes); each later read is one SMC
/// call per present key, a few milliseconds in all.
final class TemperatureReader {
    private let smc: SMC
    private var keys: [String]?

    init(smc: SMC) {
        self.smc = smc
    }

    func read() -> [(name: String, celsius: Double)] {
        let keys = self.keys ?? SensorSummary.candidateKeys.filter { smc.read($0) != nil }
        self.keys = keys
        return keys.compactMap { key in smc.value(key).map { (key, $0) } }
    }
}
