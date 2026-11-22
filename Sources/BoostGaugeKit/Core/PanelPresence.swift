import Foundation

/// Counts the places an item's panel is on screen: its menu bar dropdown, the Settings preview, and Overview's List
/// for CPU. The item hears `panelDidOpen` when the first appears and `panelDidClose` when the last goes, so one
/// closing doesn't stop the sampling another still shows.
@MainActor public final class PanelPresence {
    private var counts: [ItemID: Int] = [:]

    public init() {}

    public func opened(_ item: any BoostGaugeItem) {
        counts[item.id, default: 0] += 1
        if counts[item.id] == 1 { item.panelDidOpen() }
    }

    public func closed(_ item: any BoostGaugeItem) {
        guard let count = counts[item.id], count > 0 else { return }
        counts[item.id] = count - 1
        if count == 1 { item.panelDidClose() }
    }

    public func isOpen(_ id: ItemID) -> Bool { (counts[id] ?? 0) > 0 }
}
