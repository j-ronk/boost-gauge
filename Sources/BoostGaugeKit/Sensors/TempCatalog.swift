import Foundation

/// The Temperatures panel's groups, in panel order. Each one is its own hideable panel section.
public enum TempGroup: String, CaseIterable, Sendable {
    case cpu, gpu, memory, ssd, battery, powerManager, airflow, wireless

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .ssd: "SSD"
        case .battery: "Battery"
        case .powerManager: "Power Manager"
        case .airflow: "Airflow"
        case .wireless: "Wi-Fi"
        }
    }

    public var section: PanelSectionID {
        switch self {
        case .cpu: .tempsCPU
        case .gpu: .tempsGPU
        case .memory: .tempsMemory
        case .ssd: .tempsSSD
        case .battery: .tempsBattery
        case .powerManager: .tempsPowerManager
        case .airflow: .tempsAirflow
        case .wireless: .tempsWireless
        }
    }
}

public struct TempSensor: Equatable, Sendable {
    public var name: String
    public var celsius: Double
    /// False for a reading the menu bar's figure for the group leaves out (the battery's HID gas gauge), so the
    /// group row and the menu bar agree.
    public var inAverage: Bool

    public init(_ name: String, _ celsius: Double, inAverage: Bool = true) {
        self.name = name
        self.celsius = celsius
        self.inAverage = inAverage
    }
}

/// One group's sensors in catalogue order, which stays put between reads so rows don't jump about.
public struct TempGroupReading: Equatable, Sendable {
    public var group: TempGroup
    public var sensors: [TempSensor]

    public init(_ group: TempGroup, _ sensors: [TempSensor]) {
        self.group = group
        self.sensors = sensors
    }

    public var hottest: TempSensor? { sensors.max { $0.celsius < $1.celsius } }

    public var average: Double? {
        let counted = sensors.filter(\.inAverage)
        let values = (counted.isEmpty ? sensors : counted).map(\.celsius)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// The chip, as far as sensor naming cares: Stats' platform split (generation, plus Pro/Max/Ultra where key tables
/// differ) and the core counts macOS reports per performance level.
public struct ChipInfo: Equatable, Sendable {
    public enum Family: Equatable, Sendable { case m(Int), a18Pro }
    public enum Tier: Equatable, Sendable { case base, pro, max, ultra }

    public var family: Family?
    public var tier: Tier
    /// Cores in macOS's last performance level: the efficiency cores on most chips.
    public var efficiencyCores: Int
    public var totalCores: Int

    public init(family: Family?, tier: Tier = .base, efficiencyCores: Int = 0, totalCores: Int = 0) {
        self.family = family
        self.tier = tier
        self.efficiencyCores = efficiencyCores
        self.totalCores = totalCores
    }

    /// Mirrors Stats' brand-string match ("Apple M1 Max", "Apple A18 Pro").
    public static func parse(brand: String, efficiencyCores: Int, totalCores: Int) -> ChipInfo {
        let name = brand.lowercased()
        var family: Family?
        if name.contains("a18 pro") {
            family = .a18Pro
        } else if let match = name.firstMatch(of: /apple m(\d+)/), let gen = Int(match.1) {
            family = .m(gen)
        }
        let tier: Tier = name.contains("ultra") ? .ultra : name.contains("max") ? .max
            : name.contains("pro") && family != .a18Pro ? .pro : .base
        return ChipInfo(family: family, tier: tier, efficiencyCores: efficiencyCores, totalCores: totalCores)
    }

    public static func current() -> ChipInfo {
        func int(_ name: String) -> Int {
            var value: Int32 = 0
            var size = MemoryLayout<Int32>.size
            return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
        }
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var chars = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &chars, &size, nil, 0)
        let brand = String(decoding: chars.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        // Efficiency cores are the last performance level; a single-level chip has none.
        let levels = int("hw.nperflevels")
        let efficiency = levels >= 2 ? int("hw.perflevel\(levels - 1).physicalcpu") : 0
        return parse(brand: brand, efficiencyCores: efficiency, totalCores: int("hw.physicalcpu"))
    }
}

/// Which sensors the panel shows and what it calls them. Only names with a source are used: Stats' Apple Silicon
/// key tables (CPU cores, GPU, memory, airflow, NAND, battery, Wi-Fi) and the product names Apple's own HID
/// temperature services carry ("PMU tdie3", "gas gauge battery", "NAND CH0 temp"). Of the ~240 temperature keys an
/// M1 Max reports, most have no public name, so they aren't shown rather than shown with a guessed one.
public enum TempCatalog {
    public struct Entry: Equatable, Sendable {
        public var key: String
        public var group: TempGroup
        public var name: String

        public init(_ key: String, _ group: TempGroup, _ name: String) {
            self.key = key
            self.group = group
            self.name = name
        }
    }

    enum CoreKind { case efficiency, performance, superCore }

    /// Stats' per-generation core keys (Modules/Sensors/values.swift), in its numbering order.
    static func coreKeys(_ family: ChipInfo.Family) -> [(key: String, kind: CoreKind)] {
        func list(_ kind: CoreKind, _ keys: [String]) -> [(key: String, kind: CoreKind)] { keys.map { ($0, kind) } }
        switch family {
        case .m(1):
            return list(.efficiency, ["Tp09", "Tp0T"])
                + list(.performance, ["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"])
        case .m(2):
            return list(.efficiency, ["Tp1h", "Tp1t", "Tp1p", "Tp1l"])
                + list(.performance, ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"])
        case .m(3):
            return list(.efficiency, ["Te05", "Te0L", "Te0P", "Te0S"])
                + list(.performance, ["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B",
                                      "Tf4D", "Tf4E"])
        case .m(4):
            return list(.efficiency, ["Te05", "Te0S", "Te09", "Te0H"])
                + list(.performance, ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"])
        case .m(5):
            return list(.superCore, ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K"])
                + list(.performance, ["Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p",
                                      "Tp0u", "Tp0y"])
        case .m(6):
            return list(.superCore, ["Tp0j", "Tp0g", "Tp09", "Tp07"])
                + list(.performance, ["Tp0m", "Tp0L", "Tp0I", "Tp0d", "Tp0E", "Tp0G", "Tp0b", "Tp05"])
                + list(.efficiency, ["Te07", "Te08", "Te09", "Te0c", "Te0h", "Te0i"])
        case .a18Pro:
            return list(.efficiency, ["Te05", "Te0S"]) + list(.performance, ["Tp05", "Tp0D"])
        default:
            return []
        }
    }

    static func gpuKeys(_ chip: ChipInfo) -> [String] {
        switch chip.family {
        case .m(1): ["Tg05", "Tg0D", "Tg0L", "Tg0T"]
        case .m(2): ["Tg0f", "Tg0j"]
        case .m(3): ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
        case .m(4): (chip.tier == .base ? ["Tg0G", "Tg0H"] : ["Tg1U", "Tg1k"])
            + ["Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
        case .m(5): ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"]
        case .m(6): ["Tg1e", "Tg0d", "Tg0c", "Tg0b", "Tg1c", "Tg1d", "Tg07", "Tg1f", "Tg09", "Tg0a", "Tg1g", "Tg1h"]
        case .a18Pro: ["Tg05", "Tg0D", "Tg0L", "Tg0e"]
        default: []
        }
    }

    static func memoryKeys(_ family: ChipInfo.Family?) -> [String] {
        switch family {
        case .m(1): ["Tm02", "Tm06", "Tm08", "Tm09"]
        case .m(4): ["Tm0p", "Tm1p", "Tm2p"]
        default: []
        }
    }

    /// Every SMC key the panel could ask about on this chip, probed once to find which are present.
    public static func candidateKeys(_ chip: ChipInfo) -> [String] {
        var keys = chip.family.map { coreKeys($0).map(\.key) } ?? []
        keys += gpuKeys(chip) + memoryKeys(chip.family)
        keys += StatsSensorKeys.cpu.sorted() + StatsSensorKeys.gpu.sorted()
        keys += fixedEntries.map(\.key)
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    /// Stats' Apple Silicon names for the rest. TB0T isn't in Stats' table and reads as the hotter of TB1T and
    /// TB2T, so it's only shown on a Mac that has neither.
    static let fixedEntries: [Entry] = [
        Entry("TH0x", .ssd, "SSD"),
        Entry("TB1T", .battery, "Battery 1"),
        Entry("TB2T", .battery, "Battery 2"),
        Entry("TB0T", .battery, "Battery"),
        Entry("TaLP", .airflow, "Left"),
        Entry("TaRF", .airflow, "Right"),
        Entry("TW0P", .wireless, "Wi-Fi"),
    ]

    /// The SMC rows for the keys this Mac has. Per-core names are used only when the named keys present match the
    /// core counts macOS reports; otherwise the CPU rows are "CPU die 1…n", since a wrong P/E label is worse than none.
    public static func entries(present: Set<String>, chip: ChipInfo) -> [Entry] {
        var out: [Entry] = []

        let named = chip.family.map(coreKeys)?.filter { present.contains($0.key) } ?? []
        // macOS's last performance level is the table's lowest kind: efficiency cores, or performance cores on a
        // chip with none (M5's levels are super and performance).
        let table = chip.family.map(coreKeys) ?? []
        let lowest: CoreKind = table.contains { $0.kind == .efficiency } ? .efficiency : .performance
        let lowestCount = named.filter { $0.kind == lowest }.count
        if !named.isEmpty, lowestCount == chip.efficiencyCores, named.count == chip.totalCores {
            var counts: [String: Int] = [:]
            for core in named {
                let label = switch core.kind {
                case .efficiency: "Efficiency core"
                case .performance: "Performance core"
                case .superCore: "Super core"
                }
                counts[label, default: 0] += 1
                out.append(Entry(core.key, .cpu, "\(label) \(counts[label]!)"))
            }
            // Sorted so performance cores, the ones that run hot, come before efficiency cores.
            out.sort { order($0.name) < order($1.name) }
        } else {
            let dies = StatsSensorKeys.cpu.sorted().filter(present.contains)
            out += dies.enumerated().map { Entry($1, .cpu, "CPU die \($0 + 1)") }
        }

        var gpu = gpuKeys(chip).filter(present.contains)
        if gpu.isEmpty { gpu = StatsSensorKeys.gpu.sorted().filter(present.contains) }
        out += gpu.enumerated().map { Entry($1, .gpu, "GPU \($0 + 1)") }

        out += memoryKeys(chip.family).filter(present.contains).enumerated()
            .map { Entry($1, .memory, "Memory \($0 + 1)") }

        let hasCells = present.contains("TB1T") || present.contains("TB2T")
        out += fixedEntries.filter { present.contains($0.key) && !($0.key == "TB0T" && hasCells) }
        return out
    }

    private static func order(_ name: String) -> (Int, Int) {
        let rank = name.hasPrefix("Super") ? 0 : name.hasPrefix("Performance") ? 1 : 2
        return (rank, Int(name.split(separator: " ").last ?? "") ?? 0)
    }

    /// HID services report several copies of some names (one per PMU, or per gauge read-out), so each name keeps
    /// its hottest copy.
    public static func hidSensors(_ readings: [(product: String, celsius: Double)], skipSSD: Bool)
        -> [(group: TempGroup, sensor: TempSensor)] {
        var dies: [Int: Double] = [:], nand: [Int: Double] = [:]
        var gauge: Double?
        for r in readings where isValid(r.celsius) {
            if r.product == "gas gauge battery" {
                gauge = max(gauge ?? r.celsius, r.celsius)
            } else if let m = r.product.wholeMatch(of: /PMU tdie(\d+)/), let n = Int(m.1) {
                dies[n] = max(dies[n] ?? r.celsius, r.celsius)
            } else if !skipSSD, let m = r.product.wholeMatch(of: /NAND CH(\d+) temp/), let n = Int(m.1) {
                nand[n] = max(nand[n] ?? r.celsius, r.celsius)
            }
        }
        var out: [(group: TempGroup, sensor: TempSensor)] = []
        for (i, n) in nand.keys.sorted().enumerated() {
            out.append((.ssd, TempSensor(nand.count == 1 ? "SSD" : "SSD channel \(i + 1)", nand[n]!)))
        }
        if let gauge { out.append((.battery, TempSensor("Gas gauge", gauge, inAverage: false))) }
        for (i, n) in dies.keys.sorted().enumerated() {
            out.append((.powerManager, TempSensor("Die sensor \(i + 1)", dies[n]!)))
        }
        return out
    }

    /// The group a named HID service belongs to, nil for the ones the panel doesn't show.
    public static func hidGroup(_ product: String) -> TempGroup? {
        if product == "gas gauge battery" { return .battery }
        if product.wholeMatch(of: /PMU tdie\d+/) != nil { return .powerManager }
        if product.wholeMatch(of: /NAND CH\d+ temp/) != nil { return .ssd }
        return nil
    }

    /// Unpopulated keys read 0, a few read negative, and some glitch to 127 or more.
    public static func isValid(_ celsius: Double) -> Bool { celsius > 0 && celsius < 127 }

    /// Groups in panel order, empty ones dropped.
    public static func group(_ rows: [(group: TempGroup, sensor: TempSensor)]) -> [TempGroupReading] {
        TempGroup.allCases.compactMap { group in
            let sensors = rows.filter { $0.group == group && isValid($0.sensor.celsius) }.map(\.sensor)
            return sensors.isEmpty ? nil : TempGroupReading(group, sensors)
        }
    }
}
