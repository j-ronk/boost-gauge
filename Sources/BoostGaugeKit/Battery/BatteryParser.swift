import Foundation

enum BatteryParser {
    static func parse(iops: [String: Any], smartBattery sb: [String: Any], pack: [String: Any]?) -> BatterySnapshot {
        var s = BatterySnapshot()
        s.percent = int(iops["Current Capacity"]) ?? int(sb["CurrentCapacity"]) ?? 0
        if let state = iops["Power Source State"] as? String {
            s.onAC = state == "AC Power"
        } else {
            s.onAC = bool(sb["ExternalConnected"])
        }
        s.isCharging = iops["Is Charging"].map(bool) ?? bool(sb["IsCharging"])
        s.isCharged = iops["Is Charged"].map(bool) ?? bool(sb["FullyCharged"])
        s.minutesToFull = minutes(iops["Time to Full Charge"])
        s.minutesToEmpty = minutes(iops["Time to Empty"])
        s.optimizedChargingEngaged = bool(iops["Optimized Battery Charging Engaged"])

        s.voltage_mV = int(sb["Voltage"]) ?? 0
        s.amperage_mA = int(sb["InstantAmperage"]) ?? int(sb["Amperage"]) ?? 0
        s.cycleCount = int(sb["CycleCount"]) ?? 0

        let external = bool(sb["ExternalConnected"])
        if let telemetry = sb["PowerTelemetryData"] as? [String: Any] {
            s.systemLoadW = positiveWatts(milliwatts: telemetry["SystemLoad"])
            s.telemetryBatteryW = int(telemetry["BatteryPower"]).map { Double($0) / 1000 }
            if external { s.adapterInW = positiveWatts(milliwatts: telemetry["SystemPowerIn"]) }
        }
        // AdapterDetails lingers after unplugging, so only trust it while the adapter is connected.
        if external, let adapter = sb["AdapterDetails"] as? [String: Any], let watts = int(adapter["Watts"]), watts > 0 {
            s.adapterRatedW = Double(watts)
        }

        if let data = sb["BatteryData"] as? [String: Any] {
            s.designCapacity = int(data["DesignCapacity"]) ?? 0
            s.nominalCapacity = int(data["NominalChargeCapacity"]) ?? 0
            s.rawMaxCapacity = int(data["AppleRawMaxCapacity"]) ?? 0
        }
        let charger = sb["ChargerData"] as? [String: Any] ?? [:]
        s.notChargingReason = int(charger["NotChargingReason"]) ?? 0
        s.chargerInhibitReason = int(charger["ChargerInhibitReason"]) ?? int(sb["ChargerInhibitReason"]) ?? 0

        // On macOS 27 the pack temperature lives in AppleSmartBatteryPack, not AppleSmartBattery.
        if let packData = pack?["BatteryData"] as? [String: Any],
           let centi = int(packData["Temperature"]) ?? int(packData["VirtualTemperature"]) {
            s.temperatureC = Double(centi) / 100
        }
        return s
    }

    /// Apple's own Maximum Capacity, from `system_profiler SPPowerDataType`. The API behind it
    /// (IOPSCopyPowerSourcesByTypePrecise) refuses unentitled callers.
    static func maximumCapacityPercent(systemProfiler out: String) -> Int? {
        guard let line = out.split(separator: "\n").first(where: { $0.contains("Maximum Capacity:") }),
              let value = line.split(separator: ":").last else { return nil }
        let digits = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        guard let percent = Int(digits), (1...150).contains(percent) else { return nil }
        return percent
    }

    /// IOKit integers can arrive as an unsigned 64-bit bit pattern of a negative value (ioreg prints amperage that way).
    static func int(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber else { return nil }
        if CFNumberIsFloatType(n as CFNumber) { return Int(exactly: n.doubleValue.rounded()) }
        let unsigned = n.uint64Value
        if unsigned > UInt64(Int64.max) { return Int(Int64(bitPattern: unsigned)) }
        return n.intValue
    }

    private static func bool(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.intValue != 0 }
        return false
    }

    /// -1 means still calculating, 65535 means no estimate (load above adapter), and 0 means not applicable.
    private static func minutes(_ value: Any?) -> Int? {
        guard let m = int(value), m > 0, m < 65535 else { return nil }
        return m
    }

    private static func positiveWatts(milliwatts value: Any?) -> Double? {
        guard let mw = int(value), mw > 0 else { return nil }
        return Double(mw) / 1000
    }
}
