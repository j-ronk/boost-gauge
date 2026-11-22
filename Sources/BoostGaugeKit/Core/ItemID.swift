import Foundation

/// Every menu bar item, in menu bar declaration order.
public enum ItemID: String, CaseIterable, Sendable {
    case battery, cpu, gpu, memory, temps, network, disk, power
}

public struct ItemDefaults {
    /// Few items on first launch keeps the notch area clear; the rest are turned on in Settings.
    public static let shown: Set<ItemID> = [.battery, .cpu, .memory]
}
