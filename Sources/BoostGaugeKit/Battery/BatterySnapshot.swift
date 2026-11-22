import Foundation

/// One reading of the internal battery, merged from IOPowerSources, AppleSmartBattery and AppleSmartBatteryPack.
public struct BatterySnapshot: Equatable, Sendable {
    var percent = 0
    var onAC = false
    var isCharging = false
    var isCharged = false
    var minutesToFull: Int?
    var minutesToEmpty: Int?
    var voltage_mV = 0
    var amperage_mA = 0
    var systemLoadW: Double?
    var adapterInW: Double?
    var adapterRatedW: Double?
    var designCapacity = 0
    var nominalCapacity = 0
    var rawMaxCapacity = 0
    var cycleCount = 0
    var temperatureC: Double?
    var notChargingReason = 0
    var chargerInhibitReason = 0
    /// IOPS "Optimized Battery Charging Engaged": the one public-dictionary signal that macOS is holding the charge.
    var optimizedChargingEngaged = false

    /// PowerTelemetryData's BatteryPower, read in the same snapshot as SystemLoad.
    var telemetryBatteryW: Double?

    /// Positive while charging, negative while draining. Prefers telemetry: voltage times amperage is sampled at a
    /// different moment from SystemLoad, so the two rows disagreed by up to 10 W while the load changed.
    var batteryW: Double { telemetryBatteryW ?? Double(voltage_mV) * Double(amperage_mA) / 1_000_000 }

    /// Nominal over design: the closer of the two IORegistry ratios to System Settings' Maximum Capacity
    /// (89% vs 86% from raw max). It still drifts a point from Apple's figure as nominal capacity moves,
    /// so the panel prefers `BatteryParser.maximumCapacityPercent` and falls back to this.
    var healthPercent: Int? {
        guard designCapacity > 0, nominalCapacity > 0 else { return nil }
        return Int((Double(nominalCapacity) / Double(designCapacity) * 100).rounded())
    }
}
