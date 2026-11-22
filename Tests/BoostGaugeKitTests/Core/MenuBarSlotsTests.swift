import Foundation
import Testing
@testable import BoostGaugeKit

@MainActor
struct MenuBarSlotsTests {
    private func settings(shown: Set<ItemID>, order: [ItemID] = ItemID.allCases) -> (TestDefaults, AppSettings) {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        for id in ItemID.allCases { settings.setShown(id, shown.contains(id)) }
        settings.itemOrder = order
        return (suite, settings)
    }

    @Test func slotsShowItemsInSettingsOrderByScreenPosition() {
        // Live layout seen on macOS 27: slot 3 is leftmost, then slot 0, then slot 1.
        let order: [ItemID] = [.cpu, .battery, .memory, .gpu, .temps, .network, .disk, .power]
        let result = MenuBarSlots.assign(order: order, shown: [.battery, .cpu, .memory],
                                         positions: [0: 1134, 1: 1290, 3: 979])
        #expect(result == [3: .cpu, 0: .battery, 1: .memory])
    }

    @Test func onlyShownItemsOwnSlotsAndHiddenSlotsAreIgnored() {
        let result = MenuBarSlots.assign(order: ItemID.allCases, shown: [.gpu, .power],
                                         positions: [2: 900, 7: 800, 0: 100])
        #expect(result == [7: .gpu, 2: .power])
    }

    @Test func slotsNotYetPlacedTakeTheRightmostItemsInSlotOrder() {
        let result = MenuBarSlots.assign(order: [.disk, .cpu, .battery, .gpu, .memory, .temps, .network, .power],
                                         shown: [.battery, .cpu, .disk], positions: [1: 500])
        #expect(result == [1: .disk, 0: .cpu, 6: .battery])
    }

    @Test func slotIsInsertedWhileItsOwnItemIsShown() {
        let (_, settings) = settings(shown: [.cpu, .memory])
        let slots = MenuBarSlots(settings: settings, positions: { [:] })
        #expect(ItemID.allCases.indices.filter(slots.isInserted) == [1, 3])
    }

    @Test func refreshFollowsOrderChangesAndIsQuietWhenNothingChanged() {
        let (_, settings) = settings(shown: [.battery, .cpu])
        let slots = MenuBarSlots(settings: settings, positions: { [0: 300, 1: 200] })
        #expect(slots.refresh())
        #expect(slots.item(inSlot: 1) == .battery)
        #expect(slots.item(inSlot: 0) == .cpu)
        #expect(!slots.refresh())
        settings.itemOrder = [.cpu, .battery] + ItemID.allCases.filter { $0 != .cpu && $0 != .battery }
        #expect(slots.refresh())
        #expect(slots.item(inSlot: 1) == .cpu)
        #expect(slots.item(inSlot: 0) == .battery)
    }

    @Test func slotOutOfTheMenuBarFallsBackToItsOwnItem() {
        let (_, settings) = settings(shown: [.cpu])
        let slots = MenuBarSlots(settings: settings, positions: { [1: 200] })
        slots.refresh()
        #expect(slots.item(inSlot: 4) == .temps)
    }

    @Test func systemRemovingASlotHidesTheItemItShows() {
        let (_, settings) = settings(shown: [.battery, .cpu])
        let slots = MenuBarSlots(settings: settings, positions: { [0: 300, 1: 200] })
        slots.refresh()
        // Slot 1 is leftmost so it shows battery; removing it from the menu bar removes battery.
        slots.systemSetInserted(slot: 1, false)
        #expect(!settings.isShown(.battery))
        #expect(settings.isShown(.cpu))
    }

    @Test func echoOfOurOwnRemovalChangesNothing() {
        let (_, settings) = settings(shown: [.battery, .cpu])
        let slots = MenuBarSlots(settings: settings, positions: { [0: 300, 1: 200] })
        slots.refresh()
        // Settings hides cpu, so slot 1 leaves; before the slots refresh, SwiftUI echoes false for slot 1,
        // which still shows battery. That echo must not hide battery.
        settings.setShown(.cpu, false)
        slots.systemSetInserted(slot: 1, false)
        #expect(settings.isShown(.battery))
        slots.systemSetInserted(slot: 0, true)
        #expect(settings.isShown(.battery))
        #expect(!settings.isShown(.cpu))
    }

    @Test func slotNumberComesFromTheStatusWindowTitle() {
        #expect(MenuBarSlots.slot(fromTitle: "Item-0") == 0)
        #expect(MenuBarSlots.slot(fromTitle: "Item-7") == 7)
        #expect(MenuBarSlots.slot(fromTitle: "Item-8") == nil)
        #expect(MenuBarSlots.slot(fromTitle: "Item-x") == nil)
        #expect(MenuBarSlots.slot(fromTitle: "Settings") == nil)
    }
}
