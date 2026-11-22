import Foundation
import SwiftUI
import Testing
@testable import BoostGaugeKit

@MainActor
final class FakeItem: BoostGaugeItem {
    let id: ItemID
    var ticks = 0
    var lastTick: Date?

    init(_ id: ItemID) { self.id = id }

    var label: AnyView { AnyView(Text(id.rawValue)) }
    var panel: AnyView { AnyView(EmptyView()) }

    func tick(now: Date) {
        ticks += 1
        lastTick = now
    }
}

@MainActor
struct SchedulerTests {
    @Test func firesShownItems() {
        let suite = TestDefaults()
        let scheduler = Scheduler(settings: AppSettings(defaults: suite.defaults))
        let cpu = FakeItem(.cpu)
        scheduler.register(cpu)
        let now = Date(timeIntervalSince1970: 1_000)
        scheduler.fire(now: now)
        #expect(cpu.ticks == 1)
        #expect(cpu.lastTick == now)
        #expect(scheduler.items.map(\.id) == [.cpu])
        #expect(scheduler.item(.cpu) === cpu)
        #expect(scheduler.item(.gpu) == nil)
    }

    @Test func hiddenItemsNeverTick() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        let scheduler = Scheduler(settings: settings)
        let cpu = FakeItem(.cpu), gpu = FakeItem(.gpu)
        scheduler.register(cpu)
        scheduler.register(gpu)
        #expect(!settings.isShown(.gpu))

        for _ in 0..<3 { scheduler.fire(now: .now) }
        #expect(gpu.ticks == 0)
        #expect(cpu.ticks == 3)

        settings.setShown(.gpu, true)
        scheduler.fire(now: .now)
        #expect(gpu.ticks == 1)

        for id in ItemID.allCases { settings.setShown(id, false) }
        scheduler.fire(now: .now)
        #expect(gpu.ticks == 1)
        #expect(cpu.ticks == 4)
    }

    @Test func showingItemTicksImmediately() async throws {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.refreshSeconds = 10
        let scheduler = Scheduler(settings: settings)
        let cpu = FakeItem(.cpu), gpu = FakeItem(.gpu)
        scheduler.register(cpu)
        scheduler.register(gpu)
        scheduler.start()
        defer { scheduler.stop() }
        #expect(cpu.ticks == 1)
        #expect(gpu.ticks == 0)

        settings.setShown(.gpu, true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(gpu.ticks == 1)
        #expect(cpu.ticks == 1)

        settings.setShown(.gpu, false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(gpu.ticks == 1)
        settings.setShown(.gpu, true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(gpu.ticks == 2)
    }
}
