import Foundation

/// Every menu bar item, in menu bar declaration order. Each case's index is its fixed menu bar slot (`Item-<index>`),
/// which macOS remembers a position for, so new items only ever go on the end.
public enum ItemID: String, CaseIterable, Sendable {
    case battery, cpu, gpu, memory, temps, network, disk, power, overview
}

public struct ItemDefaults {
    /// Few items on first launch keeps the notch area clear; the rest are turned on in Settings.
    public static let shown: Set<ItemID> = [.battery, .cpu, .memory]
}
