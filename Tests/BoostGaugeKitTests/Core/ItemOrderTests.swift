import Foundation
import Testing
@testable import BoostGaugeKit

@MainActor
struct ItemOrderTests {
    @Test func defaultOrderIsDeclarationOrder() {
        let suite = TestDefaults()
        #expect(AppSettings(defaults: suite.defaults).itemOrder == ItemID.allCases)
    }

    @Test func orderPersistsUnderItsKey() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        let order: [ItemID] = [.power, .memory, .battery, .cpu, .gpu, .temps, .network, .disk]
        settings.itemOrder = order
        #expect(settings.itemOrder == order)
        #expect(suite.defaults.stringArray(forKey: "item.order") == order.map(\.rawValue))
        #expect(AppSettings(defaults: suite.reopen()).itemOrder == order)
    }

    @Test func unknownAndDuplicateIdsAreDropped() {
        #expect(ItemOrder.normalized(["cpu", "fans", "cpu", "battery", "", "gpu", "memory", "temps", "network", "disk", "power"])
                == [.cpu, .battery, .gpu, .memory, .temps, .network, .disk, .power])
    }

    @Test func missingIdsAreAppendedInDeclarationOrder() {
        // A stored order from before an item existed: the new item lands at the end.
        #expect(ItemOrder.normalized(["power", "cpu", "battery", "gpu", "memory", "temps", "network"])
                == [.power, .cpu, .battery, .gpu, .memory, .temps, .network, .disk])
        #expect(ItemOrder.normalized(["disk"]) == [.disk, .battery, .cpu, .gpu, .memory, .temps, .network, .power])
    }

    @Test func missingOrCorruptStoredValueFallsBack() {
        #expect(ItemOrder.normalized(nil) == ItemID.allCases)
        #expect(ItemOrder.normalized([]) == ItemID.allCases)
        let suite = TestDefaults()
        suite.defaults.set("cpu,gpu", forKey: "item.order")
        #expect(AppSettings(defaults: suite.defaults).itemOrder == ItemID.allCases)
    }

    @Test func setterNormalizes() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.itemOrder = [.disk, .disk, .cpu]
        #expect(settings.itemOrder == [.disk, .cpu, .battery, .gpu, .memory, .temps, .network, .power])
    }

    @Test func hiddenItemsKeepTheirSlot() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.itemOrder = [.power, .gpu, .battery, .cpu, .memory, .temps, .network, .disk]
        settings.setShown(.gpu, false)
        settings.setShown(.gpu, true)
        #expect(settings.itemOrder == [.power, .gpu, .battery, .cpu, .memory, .temps, .network, .disk])
    }

    @Test func movesLikeAList() {
        var order = ItemID.allCases
        ItemOrder.move(&order, fromOffsets: IndexSet(integer: 7), toOffset: 0)
        #expect(order == [.power, .battery, .cpu, .gpu, .memory, .temps, .network, .disk])
        ItemOrder.move(&order, fromOffsets: IndexSet(integer: 0), toOffset: 8)
        #expect(order == ItemID.allCases)
        ItemOrder.move(&order, fromOffsets: IndexSet([1, 2]), toOffset: 5)
        #expect(order == [.battery, .memory, .temps, .cpu, .gpu, .network, .disk, .power])
    }
}

@MainActor
struct ItemOrderDropTests {
    private let start = ItemID.allCases

    @Test func firstToLast() {
        #expect(ItemOrder.dropping(.battery, on: .power, edge: .after, in: start)
                == [.cpu, .gpu, .memory, .temps, .network, .disk, .power, .battery])
        #expect(ItemOrder.dropping(.battery, on: .power, edge: .before, in: start)
                == [.cpu, .gpu, .memory, .temps, .network, .disk, .battery, .power])
    }

    @Test func lastToFirst() {
        #expect(ItemOrder.dropping(.power, on: .battery, edge: .before, in: start)
                == [.power, .battery, .cpu, .gpu, .memory, .temps, .network, .disk])
        #expect(ItemOrder.dropping(.power, on: .battery, edge: .after, in: start)
                == [.battery, .power, .cpu, .gpu, .memory, .temps, .network, .disk])
    }

    @Test func adjacentSwaps() {
        #expect(ItemOrder.dropping(.cpu, on: .gpu, edge: .after, in: start).prefix(3) == [.battery, .gpu, .cpu])
        #expect(ItemOrder.dropping(.gpu, on: .cpu, edge: .before, in: start).prefix(3) == [.battery, .gpu, .cpu])
        // Already in place: dropping cpu just after battery changes nothing.
        #expect(ItemOrder.dropping(.cpu, on: .battery, edge: .after, in: start) == start)
        #expect(ItemOrder.dropping(.cpu, on: .gpu, edge: .before, in: start) == start)
    }

    @Test func dropOnSelfIsNoOp() {
        for edge in [ItemOrder.DropEdge.before, .after] {
            #expect(ItemOrder.dropping(.memory, on: .memory, edge: edge, in: start) == start)
        }
    }

    @Test func unknownIdsAreNoOp() {
        let partial: [ItemID] = [.cpu, .gpu]
        #expect(ItemOrder.dropping(.power, on: .cpu, edge: .before, in: partial) == partial)
        #expect(ItemOrder.dropping(.cpu, on: .power, edge: .before, in: partial) == partial)
    }

    @Test func liveEdgeFollowsDragDirection() {
        #expect(ItemOrder.liveEdge(dragging: .battery, over: .disk, in: start) == .after)
        #expect(ItemOrder.liveEdge(dragging: .disk, over: .battery, in: start) == .before)
    }
}
