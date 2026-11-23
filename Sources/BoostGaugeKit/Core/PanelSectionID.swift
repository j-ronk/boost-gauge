import Foundation

/// Every section of every item's panel that Settings can hide, in panel order. Headers and footers always show.
/// Raw values are stored in UserDefaults keys, so never rename one.
public enum PanelSectionID: String, CaseIterable, Sendable {
    case batteryEnergyMode = "battery.energyMode"
    case batteryHistory = "battery.history"
    case batteryPowerChart = "battery.powerChart"
    case batteryPower = "battery.power"
    case batteryHealth = "battery.health"
    case batteryUsingEnergy = "battery.usingEnergy"
    case cpuChart = "cpu.chart"
    case cpuCores = "cpu.cores"
    case cpuDetails = "cpu.details"
    case cpuTopProcesses = "cpu.topProcesses"
    case gpuChart = "gpu.chart"
    case gpuDetails = "gpu.details"
    case gpuTopApps = "gpu.topApps"
    case memoryChart = "memory.chart"
    case memoryUsage = "memory.usage"
    case memoryTopApps = "memory.topApps"
    case tempsChart = "temps.chart"
    case tempsCPU = "temps.cpu"
    case tempsGPU = "temps.gpu"
    case tempsMemory = "temps.memory"
    case tempsSSD = "temps.ssd"
    case tempsBattery = "temps.battery"
    case tempsPowerManager = "temps.powerManager"
    case tempsAirflow = "temps.airflow"
    case tempsWireless = "temps.wireless"
    case tempsFans = "temps.fans"
    case networkChart = "network.chart"
    case networkConnection = "network.connection"
    case diskChart = "disk.chart"
    case diskStorage = "disk.storage"
    case powerChart = "power.chart"
    case powerPower = "power.power"

    public var item: ItemID {
        let prefix = rawValue.prefix { $0 != "." }
        // Every raw value starts with an ItemID raw value; the test suite checks it.
        return ItemID(rawValue: String(prefix))!
    }

    /// The toggle's name in Settings: the panel's own section heading, except where that heading alone is unclear.
    public var title: String {
        switch self {
        case .batteryEnergyMode: "Energy Mode"
        case .batteryHistory: "Charge"
        // Beside the Charge toggle, "Chart" alone wouldn't say which.
        case .batteryPowerChart: "Power Chart"
        // System and Battery watts moved into the chart's legend; adapter and fans stay.
        case .batteryPower, .powerPower, .cpuDetails, .gpuDetails, .memoryUsage: "Details"
        case .cpuChart, .gpuChart, .memoryChart, .tempsChart, .networkChart, .diskChart, .powerChart: "Chart"
        case .batteryHealth: "Health"
        case .batteryUsingEnergy: "Using Energy"
        case .cpuCores: "Cores Chart"
        case .cpuTopProcesses: "Top Processes"
        case .gpuTopApps, .memoryTopApps: "Top Apps"
        case .tempsCPU, .tempsGPU, .tempsMemory, .tempsSSD, .tempsBattery, .tempsPowerManager, .tempsAirflow,
             .tempsWireless:
            TempGroup.allCases.first { $0.section == self }!.title
        case .tempsFans: "Fans"
        case .networkConnection: "Connection"
        case .diskStorage: "Storage"
        }
    }

    public static func sections(of item: ItemID) -> [PanelSectionID] {
        allCases.filter { $0.item == item }
    }
}
