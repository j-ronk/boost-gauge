import Foundation

/// Every section of every item's panel that Settings can hide, in panel order. Headers and footers always show.
/// Raw values are stored in UserDefaults keys, so never rename one.
public enum PanelSectionID: String, CaseIterable, Sendable {
    case batteryEnergyMode = "battery.energyMode"
    case batteryHistory = "battery.history"
    case batteryPower = "battery.power"
    case batteryPowerChart = "battery.powerChart"
    case batteryHealth = "battery.health"
    case batteryUsingEnergy = "battery.usingEnergy"
    case cpuCores = "cpu.cores"
    case cpuDetails = "cpu.details"
    case cpuTopProcesses = "cpu.topProcesses"
    case gpuChart = "gpu.chart"
    case gpuDetails = "gpu.details"
    case gpuTopApps = "gpu.topApps"
    case memoryUsage = "memory.usage"
    case memoryTopApps = "memory.topApps"
    case tempsCPU = "temps.cpu"
    case tempsGPU = "temps.gpu"
    case tempsMemory = "temps.memory"
    case tempsSSD = "temps.ssd"
    case tempsBattery = "temps.battery"
    case tempsPowerManager = "temps.powerManager"
    case tempsAirflow = "temps.airflow"
    case tempsWireless = "temps.wireless"
    case tempsFans = "temps.fans"
    case networkSpeed = "network.speed"
    case networkChart = "network.chart"
    case networkConnection = "network.connection"
    case diskStorage = "disk.storage"
    case diskActivity = "disk.activity"
    case powerPower = "power.power"
    case powerChart = "power.chart"

    public var item: ItemID {
        let prefix = rawValue.prefix { $0 != "." }
        // Every raw value starts with an ItemID raw value; the test suite checks it.
        return ItemID(rawValue: String(prefix))!
    }

    /// The toggle's name in Settings: the panel's own section heading, except where that heading alone is unclear.
    public var title: String {
        switch self {
        case .batteryEnergyMode: "Energy Mode"
        case .batteryHistory: "History"
        case .batteryPower, .powerPower: "Power"
        // Beside the Power toggle, "Last 10 Minutes" wouldn't say which chart.
        case .batteryPowerChart: "Power Chart"
        case .gpuChart, .networkChart, .powerChart: "Last 10 Minutes"
        case .batteryHealth: "Health"
        case .batteryUsingEnergy: "Using Energy"
        case .cpuCores: "Cores Chart"
        case .cpuDetails, .gpuDetails: "Details"
        case .cpuTopProcesses: "Top Processes"
        case .gpuTopApps, .memoryTopApps: "Top Apps"
        case .memoryUsage: "Usage"
        case .tempsCPU, .tempsGPU, .tempsMemory, .tempsSSD, .tempsBattery, .tempsPowerManager, .tempsAirflow,
             .tempsWireless:
            TempGroup.allCases.first { $0.section == self }!.title
        case .tempsFans: "Fans"
        case .networkSpeed: "Speed"
        case .networkConnection: "Connection"
        case .diskStorage: "Storage"
        case .diskActivity: "Activity"
        }
    }

    public static func sections(of item: ItemID) -> [PanelSectionID] {
        allCases.filter { $0.item == item }
    }
}
