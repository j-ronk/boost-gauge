import Foundation
import SwiftUI

/// Raw values match `pmset`'s source flags order: battery is `-b`, adapter is `-c`.
public enum PowerSource: Int, Sendable {
    case battery = 0, adapter = 1
}

/// Raw values are `pmset powermode` values.
public enum EnergyMode: Int, Sendable {
    case automatic = 0, low = 1, high = 2

    /// System Settings order.
    public static let pickerOrder: [EnergyMode] = [.low, .automatic, .high]

    public var title: String {
        switch self {
        case .low: "Low Power"
        case .automatic: "Automatic"
        case .high: "High Power"
        }
    }
}

public enum HelperStatus: Sendable {
    case enabled, requiresApproval, notRegistered, unavailable
}

@MainActor public protocol EnergyModeService: AnyObject {
    var helperStatus: HelperStatus { get }
    func openLoginItems()
    /// The whole "Energy Mode · <source>" section, picker included.
    func makeSection() -> AnyView
}
