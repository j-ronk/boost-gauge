import Foundation

enum ChargeState: Equatable {
    case charging(Int?)
    case onBattery(Int?)
    case charged
    case drainingOnAC
    case onHold
    case notCharging

    /// Draining beats IOPS "Is Charging", which stays true while the load exceeds the adapter.
    static func classify(_ s: BatterySnapshot) -> ChargeState {
        guard s.onAC else { return .onBattery(s.minutesToEmpty) }
        if s.isCharged { return .charged }
        if s.batteryW < -0.5 { return .drainingOnAC }
        if s.isCharging { return .charging(s.minutesToFull) }
        if isHeld(s) { return .onHold }
        return .notCharging
    }

    /// The exact "Charging On Hold" state lives behind a private powerd entitlement (IOPSCopyChargeStatus returns
    /// kIOReturnNotPrivileged), so this infers it. Optimized Battery Charging sets an IOPS key; a charge limit or a
    /// third-party limiter stops the charger with a reason code. A stop reason well below any charge limit
    /// (macOS limits start at 80%) is treated as a thermal or fault stop instead.
    private static func isHeld(_ s: BatterySnapshot) -> Bool {
        if s.optimizedChargingEngaged || s.chargerInhibitReason != 0 { return true }
        return s.notChargingReason != 0 && s.percent >= holdFloorPercent
    }

    static let holdFloorPercent = 75

    var headerText: String {
        switch self {
        case let .charging(m): m.map { "Charging · \(Format.hm(minutes: $0)) to full" } ?? "Charging"
        case let .onBattery(m): m.map { "On Battery · \(Format.hm(minutes: $0)) left" } ?? "On Battery"
        case .charged: "Charged"
        case .drainingOnAC: "Plugged In · Draining"
        case .onHold: "Charging On Hold"
        case .notCharging: "Not Charging"
        }
    }
}
