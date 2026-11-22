import Foundation
import Testing
@testable import BoostGaugeKit

@MainActor
struct OverviewSettingsTests {
    @Test func styleDefaultsToBarsAndPersists() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        #expect(settings.overviewStyle == .bars)
        settings.overviewStyle = .tiles
        #expect(suite.defaults.string(forKey: "overview.style") == "tiles")
        #expect(AppSettings(defaults: suite.reopen()).overviewStyle == .tiles)
        settings.overviewStyle = .list
        #expect(AppSettings(defaults: suite.reopen()).overviewStyle == .list)
    }

    @Test func unknownStoredStyleFallsBackToBars() {
        let suite = TestDefaults()
        suite.defaults.set("grid", forKey: "overview.style")
        #expect(AppSettings(defaults: suite.defaults).overviewStyle == .bars)
    }

    @Test func overviewIsOffAndHidesNothingByDefault() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        #expect(!settings.isShown(.overview))
        #expect(!settings.overviewHidesOthers)
        #expect(!settings.overviewReplacesOthers)
        for id in ItemDefaults.shown { #expect(settings.isInMenuBar(id)) }
    }

    @Test func hideOthersTakesEveryOtherItemOutOnlyWhileOverviewIsShown() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.overviewHidesOthers = true
        // Overview hidden: nothing changes.
        #expect(settings.isInMenuBar(.cpu))
        #expect(!settings.isInMenuBar(.overview))

        settings.setShown(.overview, true)
        #expect(settings.overviewReplacesOthers)
        #expect(settings.isInMenuBar(.overview))
        for id in ItemID.allCases where id != .overview { #expect(!settings.isInMenuBar(id), "\(id)") }
        // Each item's own choice survives, so turning it off restores the same items.
        #expect(settings.isShown(.cpu) && settings.isShown(.battery) && !settings.isShown(.gpu))

        settings.overviewHidesOthers = false
        #expect(settings.isInMenuBar(.cpu) && settings.isInMenuBar(.battery) && !settings.isInMenuBar(.gpu))
        #expect(settings.isInMenuBar(.overview))
    }

    @Test func hideOthersPersistsAndSkipsNoOpWrites() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.overviewHidesOthers = false
        settings.overviewStyle = .bars
        #expect(suite.defaults.object(forKey: "overview.hidesOthers") == nil)
        #expect(suite.defaults.object(forKey: "overview.style") == nil)
        settings.overviewHidesOthers = true
        #expect(AppSettings(defaults: suite.reopen()).overviewHidesOthers)
    }

    @Test func settingsModelBindsOverviewChoices() {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let model = SettingsModel(ctx, loginItem: .inert)
        model.overviewStyle.wrappedValue = .list
        model.overviewHidesOthers.wrappedValue = true
        #expect(ctx.settings.overviewStyle == .list)
        #expect(!model.isReplacedByOverview(.cpu))
        model.shown(.overview).wrappedValue = true
        #expect(model.isReplacedByOverview(.cpu))
        #expect(!model.isReplacedByOverview(.overview))
        #expect(OverviewStyle.allCases.map(SettingsModel.title) == ["Bars", "List", "Tiles"])
    }

    @Test func overviewLeadsTheOrder() {
        #expect(ItemOrder.default.first == .overview)
        // A stored order from before Overview existed: it joins at the front.
        #expect(ItemOrder.normalized(["cpu", "battery"]).prefix(3) == [.overview, .cpu, .battery])
        // Once placed, it stays where the user put it.
        #expect(ItemOrder.normalized(["cpu", "overview", "battery"]).prefix(3) == [.cpu, .overview, .battery])
    }
}

@MainActor
struct OverviewMenuBarTests {
    @Test func replacedItemsStopTickingAndLeaveTheirSlots() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        let scheduler = Scheduler(settings: settings)
        let cpu = FakeItem(.cpu), overview = FakeItem(.overview)
        scheduler.register(cpu)
        scheduler.register(overview)
        settings.setShown(.overview, true)
        scheduler.fire(now: .now)
        #expect(cpu.ticks == 1 && overview.ticks == 1)

        settings.overviewHidesOthers = true
        scheduler.fire(now: .now)
        #expect(cpu.ticks == 1)
        #expect(overview.ticks == 2)

        let slots = MenuBarSlots(settings: settings, positions: { [:] })
        #expect(ItemID.allCases.indices.filter(slots.isInserted) == [ItemID.allCases.firstIndex(of: .overview)!])
        slots.refresh()
        #expect(slots.assignment == [8: .overview])
    }

    @Test func takingOverviewOutOfTheMenuBarBringsTheOthersBack() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.setShown(.overview, true)
        settings.overviewHidesOthers = true
        let slots = MenuBarSlots(settings: settings, positions: { [:] })
        slots.refresh()
        // SwiftUI echoing a replaced slot's removal isn't the user hiding that item.
        slots.systemSetInserted(slot: 1, false)
        #expect(settings.isShown(.cpu))
        // Cmd-dragging Overview out is.
        slots.systemSetInserted(slot: 8, false)
        #expect(!settings.isShown(.overview))
        #expect(settings.isInMenuBar(.cpu))
    }
}

@MainActor
struct OverviewGlyphTests {
    @Test func levelsScaleToThirteenPointsWithAFloor() {
        #expect(OverviewGlyph.heights(cpu: 100, gpu: 50, memory: 0) == [13, 6.5, 2])
        #expect(OverviewGlyph.heights(cpu: 29, gpu: 100, memory: 49) == [4, 13, 6.5])
    }

    @Test func missingOrGarbageReadingsDrawAnEmptyTrack() {
        #expect(OverviewGlyph.heights(cpu: nil, gpu: .nan, memory: .infinity) == [0, 0, 0])
        #expect(OverviewGlyph.heights(cpu: 140, gpu: -5, memory: nil) == [13, 2, 0])
    }

    @Test func smallMovesReuseTheSameImage() {
        let a = OverviewGlyph(heights: OverviewGlyph.heights(cpu: 30, gpu: 30, memory: 30)).image
        let b = OverviewGlyph(heights: OverviewGlyph.heights(cpu: 31, gpu: 30, memory: 30)).image
        let c = OverviewGlyph(heights: OverviewGlyph.heights(cpu: 60, gpu: 30, memory: 30)).image
        #expect(a === b)
        #expect(a !== c)
        #expect(a.isTemplate)
        #expect(a.size == OverviewGlyph.size)
    }
}

@MainActor
struct OverviewItemTests {
    /// Every source the Overview reads, with counters on the reads that cost something.
    @MainActor final class Rig {
        let suite = TestDefaults()
        let ctx: AppContext
        let feed = TickFeed()
        let cpu: CPUItem
        var overview: OverviewItem!
        var temperatureReads = 0
        var gpuReads = 0
        var batteryReads = 0

        init() {
            ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
            cpu = CPUItem(ctx, readTicks: feed.read)
            var battery = BatterySnapshot()
            battery.percent = 34
            battery.systemLoadW = 18.2
            ctx.scheduler.register(cpu)
            ctx.scheduler.register(GPUItem(ctx, read: { [unowned self] in self.gpuReads += 1; return 40 }))
            ctx.scheduler.register(MemoryItem(ctx, read: {
                MemoryStats(usedBytes: 8 << 30, totalBytes: 16 << 30, usedPercent: 50)
            }))
            ctx.scheduler.register(TempsItem(ctx, readTemperatures: { [unowned self] in
                self.temperatureReads += 1
                return [("Tp01", 58), ("Tg05", 54)]
            }, readFans: { [] }))
            overview = OverviewItem(ctx, readBattery: { [unowned self] _ in self.batteryReads += 1; return battery })
            ctx.scheduler.register(overview)
        }
    }

    @Test func feedsGlyphSourcesThatAreOutOfTheMenuBar() {
        let rig = Rig()
        let s = rig.ctx.settings
        for id in ItemID.allCases { s.setShown(id, id == .overview) }
        rig.ctx.scheduler.fire(now: .now)
        rig.ctx.scheduler.fire(now: .now.addingTimeInterval(2))
        let item = rig.overview!
        #expect(item.model.reading.cpu == 75)
        #expect(item.model.reading.gpu == 40)
        #expect(item.model.reading.memory?.usedPercent == 50)
        // 75% of 13 pt is 9.75, to the half point 10; 40% is 5.2, so 5.
        #expect(item.model.glyph == [10, 5, 6.5])
        // Panel-only figures wait for the panel.
        #expect(rig.temperatureReads == 0)
        #expect(rig.batteryReads == 0)
    }

    @Test func neverTicksASourceTheSchedulerAlreadyTicked() {
        let rig = Rig()
        let s = rig.ctx.settings
        for id in ItemID.allCases { s.setShown(id, id == .overview || id == .gpu || id == .cpu) }
        for i in 0..<3 { rig.ctx.scheduler.fire(now: .now.addingTimeInterval(Double(i) * 2)) }
        #expect(rig.gpuReads == 3)
        #expect(rig.feed.reads == 3)
    }

    @Test func replacedItemsKeepUpdatingThroughOverview() {
        let rig = Rig()
        let s = rig.ctx.settings
        s.setShown(.overview, true)
        s.setShown(.gpu, true)
        s.overviewHidesOthers = true
        for i in 0..<3 { rig.ctx.scheduler.fire(now: .now.addingTimeInterval(Double(i) * 2)) }
        #expect(rig.gpuReads == 3)
        #expect(rig.feed.reads == 3)
        #expect(rig.overview.model.reading.cpu == 75)
    }

    @Test func openPanelReadsTheRestAndStopsWhenClosed() {
        let rig = Rig()
        let s = rig.ctx.settings
        for id in ItemID.allCases { s.setShown(id, id == .overview) }
        let item = rig.overview!
        item.panelDidOpen()
        #expect(rig.temperatureReads == 1)
        #expect(rig.batteryReads == 1)
        #expect(item.model.reading.temps.cpu == 58)
        #expect(item.model.reading.battery?.percent == 34)
        rig.ctx.scheduler.fire(now: .now)
        #expect(rig.temperatureReads == 2)
        item.panelDidClose()
        rig.ctx.scheduler.fire(now: .now.addingTimeInterval(2))
        #expect(rig.temperatureReads == 2)
        #expect(item.model.topProcesses == nil)
    }

    @Test func sparklinesTakeOnlyFreshReadingsAndStayShort() {
        let rig = Rig()
        let s = rig.ctx.settings
        for id in ItemID.allCases { s.setShown(id, id == .overview) }
        for i in 0..<(OverviewModel.sparkLength + 5) { rig.ctx.scheduler.fire(now: .now.addingTimeInterval(Double(i) * 2)) }
        let sparks = rig.overview.model.sparks
        #expect(sparks[.gpu]?.count == OverviewModel.sparkLength)
        #expect(sparks[.hottest] == nil)
        #expect(sparks[.battery] == nil)
        #expect(sparks[.cpuTemp] == nil, "Bars-only metrics have no line")
    }

    @Test func hidingOverviewDropsTheLines() async throws {
        let rig = Rig()
        let s = rig.ctx.settings
        for id in ItemID.allCases { s.setShown(id, id == .overview) }
        rig.ctx.scheduler.fire(now: .now)
        #expect(rig.overview.model.sparks[.gpu]?.count == 1)
        s.setShown(.overview, false)
        // The watcher reads the new value on the next main-actor turn.
        try await Task.sleep(for: .milliseconds(50))
        #expect(rig.overview.model.sparks.isEmpty)
    }

    @Test func overviewAndTheCPUPanelShareOneProcessBaseline() {
        let rig = Rig()
        let cpu = FakeItem(.cpu)
        let presence = rig.ctx.panels
        presence.opened(cpu)
        rig.overview.panelDidOpen()
        #expect(presence.isOpen(.cpu))
        rig.overview.panelDidClose()
        #expect(presence.isOpen(.cpu), "the CPU panel is still open")
    }
}

@MainActor
struct OverviewTextTests {
    @Test func panelStrings() {
        let disk = DiskCapacity(name: "Macintosh HD", available: 412_000_000_000, total: 981_000_000_000)
        #expect(OverviewText.diskFree(disk) == "412 GB")
        #expect(OverviewText.diskUsed(disk) == "58% used")
        #expect(OverviewText.diskFree(DiskCapacity(name: "x", available: 1_200_000_000_000, total: 2_000_000_000_000)) == "1.2 TB")
        #expect(OverviewText.watts(18.2) == "18 W")
        #expect(OverviewText.watts(nil) == "—")
        #expect(OverviewText.download(NetworkRate(up: 89_000, down: 95_000), .bytes) == "↓ 95 KB/s")
        #expect(OverviewText.upload(nil, .bytes) == "↑ —")
        #expect(OverviewText.memoryUsed(MemoryStats(usedBytes: UInt64(7.8 * Double(1 << 30)), totalBytes: 16 << 30, usedPercent: 49)) == "7.8 GB")
        #expect(OverviewText.temperature(58.4, .fahrenheit) == "137°F")
        #expect(OverviewText.fraction(150) == 1)
        #expect(OverviewText.fraction(nil) == nil)
    }

    @Test func sampleMatchesTheMockupFigures() {
        let r = OverviewItem.sampleModel().reading
        #expect(OverviewStyle.list.metrics.map { OverviewText.rowValue($0, r) } == ["29%", "100%", "49%", "412 GB", "72°C", "34%", "95 KB/s"])
        #expect(OverviewText.rowValue(.systemPower, r) == "18 W")
        #expect(OverviewText.batteryStatus(r.battery) == "Charging · 1:54 to full")
    }
}
