import Foundation

/// The user's left-to-right order of menu bar items. Every item has a slot, shown or not.
public enum ItemOrder {
    /// Overview opens the condensed panel for the items beside it, so it leads them.
    public static let `default` = [ItemID.overview] + ItemID.allCases.filter { $0 != .overview }

    /// Drops unknown and repeated ids, then adds any missing item in declaration order, so an item added in a later
    /// version lands at the end. Overview is the exception: it joins at the front, where `default` puts it.
    public static func normalized(_ raw: [String]?) -> [ItemID] {
        normalized((raw ?? []).compactMap(ItemID.init(rawValue:)))
    }

    public static func normalized(_ ids: [ItemID]) -> [ItemID] {
        var seen = Set<ItemID>()
        let known = ids.filter { seen.insert($0).inserted }
        let lead: [ItemID] = seen.contains(.overview) ? [] : [.overview]
        return lead + known + ItemID.allCases.filter { !seen.contains($0) && $0 != .overview }
    }

    /// Same semantics as SwiftUI's `onMove`: `destination` is an index in the list before the move.
    public static func move(_ order: inout [ItemID], fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { order[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { order.remove(at: index) }
        order.insert(contentsOf: moving, at: min(destination - before, order.count))
    }

    public enum DropEdge: Sendable { case before, after }

    /// The order after dropping `dragged` on the `edge` side of `target`. Unknown ids and a drop on itself change nothing.
    public static func dropping(_ dragged: ItemID, on target: ItemID, edge: DropEdge, in order: [ItemID]) -> [ItemID] {
        guard dragged != target, let from = order.firstIndex(of: dragged), let to = order.firstIndex(of: target) else {
            return order
        }
        var result = order
        move(&result, fromOffsets: IndexSet(integer: from), toOffset: edge == .before ? to : to + 1)
        return result
    }

    /// While dragging, a row takes the place of the row it passes over, so it lands beyond it in the drag's direction.
    public static func liveEdge(dragging: ItemID, over target: ItemID, in order: [ItemID]) -> DropEdge {
        guard let from = order.firstIndex(of: dragging), let to = order.firstIndex(of: target) else { return .before }
        return from < to ? .after : .before
    }
}
