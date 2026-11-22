import AppKit
import Observation

/// Puts Boost Gauge's items in the menu bar in the user's order. macOS 27 remembers a position for each status item
/// and ignores insertion order and `Preferred Position`, so the menu bar scenes stay put as fixed slots
/// (`Item-0`…`Item-8`) and each slot shows whichever item belongs at its place, left to right.
///
/// A Cmd-drag in the menu bar moves a slot's window, and AppKit says nothing more. So when the same slots are all
/// placed but sit in a new left-to-right order, the user moved one: each keeps the item it showed and Settings takes
/// the order from the screen. Any other change (a slot shown, hidden or not yet placed) is Boost Gauge's own, and the
/// slots follow Settings instead.
@MainActor @Observable public final class MenuBarSlots {
    /// Slot → the item it shows. Slots out of the menu bar aren't listed.
    public private(set) var assignment: [Int: ItemID] = [:]
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let positions: @MainActor () -> [Int: Double]
    @ObservationIgnored private var moveObserver: NSObjectProtocol?
    /// The shown slots left to right at the last pass, while every one was placed.
    @ObservationIgnored private var lastPlacement: [Int]?

    public init(settings: AppSettings, positions: @escaping @MainActor () -> [Int: Double] = MenuBarSlots.statusWindowPositions) {
        self.settings = settings
        self.positions = positions
    }

    /// Slot k is in the menu bar while item k is, so the slots macOS has placed stay the same
    /// across relaunches. Only what each one shows moves.
    public func isInserted(_ slot: Int) -> Bool { settings.isInMenuBar(ItemID.allCases[slot]) }

    public func item(inSlot slot: Int) -> ItemID { assignment[slot] ?? ItemID.allCases[slot] }

    /// Returns whether anything changed. Assigning the same slots again would re-render every label.
    @discardableResult public func refresh() -> Bool {
        let shown = Set(ItemID.allCases.filter(settings.isInMenuBar))
        let positions = positions()
        adoptUserMove(shown: shown, positions: positions)
        let next = Self.assign(order: settings.itemOrder, shown: shown, positions: positions)
        guard next != assignment else { return false }
        assignment = next
        return true
    }

    /// Writes the screen's order to Settings after a Cmd-drag, so the assignment that follows leaves every slot
    /// showing what it showed. Writing Settings re-runs `refresh`, which then finds nothing new.
    private func adoptUserMove(shown: Set<ItemID>, positions: [Int: Double]) {
        let slots = ItemID.allCases.indices.filter { shown.contains(ItemID.allCases[$0]) }
        guard slots.allSatisfy({ (positions[$0] ?? 0) > 0 }) else {
            lastPlacement = nil
            return
        }
        let placement = slots.sorted { positions[$0]! < positions[$1]! }
        defer { lastPlacement = placement }
        guard let last = lastPlacement, last != placement, Set(last) == Set(placement) else { return }
        let onScreen = placement.compactMap { assignment[$0] }
        guard onScreen.count == placement.count else { return }
        let next = ItemOrder.reordering(settings.itemOrder, shownAs: onScreen)
        if next != settings.itemOrder { settings.itemOrder = next }
    }

    /// The menu bar's own visibility changes for a slot. SwiftUI also echoes the changes Boost Gauge makes, and
    /// those already agree with Settings, so only a disagreement is the user taking the item they saw out.
    public func systemSetInserted(slot: Int, _ inserted: Bool) {
        guard inserted != isInserted(slot) else { return }
        settings.setShown(item(inSlot: slot), inserted)
    }

    /// Follows Settings, and the slots as macOS places or moves them, for the life of the app.
    public func start() {
        refresh()
        track()
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: nil,
                                                              queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow, Self.slot(fromTitle: window.title) != nil else { return }
            MainActor.assumeIsolated { _ = self?.refresh() }
        }
    }

    private func track() {
        withObservationTracking {
            _ = settings.itemOrder
            for id in ItemID.allCases { _ = settings.isInMenuBar(id) }
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                self.track()
            }
        }
    }

    /// Shown items fill the shown slots left to right. A slot macOS hasn't placed yet sorts last; the move
    /// that places it triggers another pass.
    static func assign(order: [ItemID], shown: Set<ItemID>, positions: [Int: Double]) -> [Int: ItemID] {
        let slots = ItemID.allCases.indices.filter { shown.contains(ItemID.allCases[$0]) }
        let placed = slots.filter { (positions[$0] ?? 0) > 0 }.sorted { positions[$0]! < positions[$1]! }
        let unplaced = slots.filter { (positions[$0] ?? 0) <= 0 }
        return Dictionary(uniqueKeysWithValues: zip(placed + unplaced, order.filter(shown.contains)))
    }

    /// SwiftUI names each menu bar scene's status window after its autosave name, `Item-<scene index>`.
    nonisolated static func slot(fromTitle title: String) -> Int? {
        guard title.hasPrefix("Item-"), let n = Int(title.dropFirst(5)), ItemID.allCases.indices.contains(n) else { return nil }
        return n
    }

    /// Left edge of each slot's status window, read in-process. Slots out of the menu bar sit at x = 0.
    public static func statusWindowPositions() -> [Int: Double] {
        var out: [Int: Double] = [:]
        for window in NSApp.windows {
            if let slot = slot(fromTitle: window.title), window.isVisible { out[slot] = window.frame.minX }
        }
        return out
    }
}
