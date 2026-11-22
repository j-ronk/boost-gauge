import Foundation
import SwiftUI
import Testing
@testable import BoostGaugeKit

/// Cmd-drag in the menu bar and the Settings order, kept in step both ways. Headless: the status windows' left
/// edges are fed in, as `statusWindowPositions` reads them after a drag.
@MainActor
struct MenuBarSyncTests {
    @MainActor final class Screen {
        var positions: [Int: Double] = [:]
    }

    private func slot(_ id: ItemID) -> Int { ItemID.allCases.firstIndex(of: id)! }

    /// Battery, CPU and Memory shown (the defaults), placed left to right.
    private func makeSlots() -> (MenuBarSlots, AppSettings, Screen) {
        let settings = AppSettings(defaults: TestDefaults().defaults)
        let screen = Screen()
        screen.positions = [slot(.battery): 100, slot(.cpu): 200, slot(.memory): 300]
        let slots = MenuBarSlots(settings: settings, positions: { screen.positions })
        slots.refresh()
        return (slots, settings, screen)
    }

    @Test func cmdDragInTheMenuBarRewritesTheSettingsOrder() {
        let (slots, settings, screen) = makeSlots()
        #expect(slots.assignment == [slot(.battery): .battery, slot(.cpu): .cpu, slot(.memory): .memory])
        // Memory's window dragged to the far left.
        screen.positions[slot(.memory)] = 50
        slots.refresh()
        #expect(settings.itemOrder.filter(settings.isShown) == [.memory, .battery, .cpu])
        // Every slot keeps what it showed, so nothing on screen jumps back.
        #expect(slots.assignment == [slot(.battery): .battery, slot(.cpu): .cpu, slot(.memory): .memory])
        // Hidden items keep their places in the order.
        #expect(settings.itemOrder.first == .overview)
        #expect(settings.itemOrder.firstIndex(of: .gpu) == 3)
    }

    @Test func aSecondPassAfterTheDragChangesNothing() {
        let (slots, settings, screen) = makeSlots()
        screen.positions[slot(.battery)] = 250
        slots.refresh()
        let order = settings.itemOrder
        #expect(!slots.refresh())
        #expect(settings.itemOrder == order)
    }

    @Test func aSettingsReorderMovesWhatTheSlotsShow() {
        let (slots, settings, _) = makeSlots()
        settings.itemOrder = [.memory, .cpu, .battery] + settings.itemOrder.filter { ![.memory, .cpu, .battery].contains($0) }
        slots.refresh()
        #expect(slots.assignment == [slot(.battery): .memory, slot(.cpu): .cpu, slot(.memory): .battery])
        #expect(settings.itemOrder.prefix(3) == [.memory, .cpu, .battery], "the screen didn't move, so Settings stands")
    }

    @Test func aNewlyShownItemFollowsSettingsWherevermacOSPutsIt() {
        let (slots, settings, screen) = makeSlots()
        let before = settings.itemOrder
        settings.setShown(.gpu, true)
        slots.refresh()
        // macOS places the new slot at the far left; that's not the user moving anything.
        screen.positions[slot(.gpu)] = 10
        slots.refresh()
        #expect(settings.itemOrder == before)
        #expect(slots.assignment[slot(.gpu)] == .battery)
        #expect(Set(slots.assignment.values) == [.battery, .cpu, .gpu, .memory])
    }

    @Test func otherItemsShiftingOursAlongIsntAMove() {
        let (slots, settings, screen) = makeSlots()
        let before = settings.itemOrder
        for key in screen.positions.keys { screen.positions[key]! -= 40 }
        slots.refresh()
        #expect(settings.itemOrder == before)
    }

    @Test func reorderingKeepsHiddenItemsInPlace() {
        let order: [ItemID] = [.overview, .battery, .cpu, .gpu, .memory]
        #expect(ItemOrder.reordering(order, shownAs: [.memory, .battery, .cpu]) == [.overview, .memory, .battery, .gpu, .cpu])
        #expect(ItemOrder.reordering(order, shownAs: [.cpu, .cpu]) == order, "a repeat is ignored")
    }
}

@MainActor
struct PanelPresenceTests {
    @MainActor final class Spy: BoostGaugeItem {
        let id: ItemID
        var opens = 0
        var closes = 0
        init(_ id: ItemID) { self.id = id }
        var label: AnyView { AnyView(EmptyView()) }
        var panel: AnyView { AnyView(EmptyView()) }
        func tick(now: Date) {}
        func panelDidOpen() { opens += 1 }
        func panelDidClose() { closes += 1 }
    }

    @Test func firstOpenAndLastCloseReachTheItem() {
        let presence = PanelPresence()
        let cpu = Spy(.cpu)
        presence.opened(cpu)
        presence.opened(cpu)
        #expect(cpu.opens == 1)
        presence.closed(cpu)
        #expect(cpu.closes == 0 && presence.isOpen(.cpu))
        presence.closed(cpu)
        #expect(cpu.closes == 1 && !presence.isOpen(.cpu))
        // An unmatched close is ignored.
        presence.closed(cpu)
        #expect(cpu.closes == 1)
    }
}
