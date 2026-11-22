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

    @Test func overviewIsOffByDefaultAndHidesNothing() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        #expect(!settings.isShown(.overview))
        settings.setShown(.overview, true)
        // Each item is ticked on or off on its own; showing Overview takes nothing else out.
        for id in ItemDefaults.shown { #expect(settings.isShown(id)) }
        #expect(suite.defaults.object(forKey: "overview.hidesOthers") == nil)
    }

    @Test func settingsModelBindsOverviewChoices() {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let model = SettingsModel(ctx, loginItem: .inert)
        model.overviewStyle.wrappedValue = .list
        #expect(ctx.settings.overviewStyle == .list)
        // The Menu Bar page's row and the Overview page's switch are one setting.
        model.shown(.overview).wrappedValue = true
        #expect(ctx.settings.isShown(.overview))
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
    @Test func overviewSitsBesideTheOtherItems() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        let scheduler = Scheduler(settings: settings)
        let cpu = FakeItem(.cpu), overview = FakeItem(.overview)
        scheduler.register(cpu)
        scheduler.register(overview)
        settings.setShown(.overview, true)
        scheduler.fire(now: .now)
        #expect(cpu.ticks == 1 && overview.ticks == 1)

        let slots = MenuBarSlots(settings: settings, positions: { [:] })
        #expect(slots.isInserted(ItemID.allCases.firstIndex(of: .overview)!))
        #expect(slots.isInserted(ItemID.allCases.firstIndex(of: .cpu)!))
    }

    @Test func cmdDraggingOverviewOutTakesOnlyOverviewOut() throws {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.setShown(.overview, true)
        let slots = MenuBarSlots(settings: settings, positions: { [:] })
        slots.refresh()
        let slot = try #require(slots.assignment.first { $0.value == .overview }?.key)
        slots.systemSetInserted(slot: slot, false)
        #expect(!settings.isShown(.overview))
        #expect(settings.isShown(.cpu))
    }
}

@MainActor
struct OverviewGlyphTests {
    @Test func levelsScaleToFourteenWholePointsWithAFloor() {
        #expect(OverviewGlyph.heights([100, 50, 0]) == [14, 7, 2])
        // 29% of 14 is 4.06; 49% is 6.86. Whole points stay crisp at 1x.
        #expect(OverviewGlyph.heights([29, 100, 49]) == [4, 14, 7])
    }

    @Test func missingOrGarbageReadingsDrawAnEmptyTrack() {
        #expect(OverviewGlyph.heights([nil, .nan, .infinity]) == [0, 0, 0])
        #expect(OverviewGlyph.heights([140, -5, nil]) == [14, 2, 0])
    }

    @Test func widthGrowsWithTheBarCount() {
        #expect(OverviewGlyph.size(bars: 1).width == 6)
        #expect(OverviewGlyph.size(bars: 3).width == 18)
        #expect(OverviewGlyph.size(bars: 6).width == 36)
        #expect(OverviewGlyph.size(bars: 6).height == StackedLabel.height)
        // Whole points everywhere, so nothing lands between pixels at 1x.
        for n in 1...6 { #expect(OverviewGlyph.size(bars: n).width.truncatingRemainder(dividingBy: 1) == 0) }
    }

    @Test func smallMovesReuseTheSameImage() {
        let a = OverviewGlyph(heights: OverviewGlyph.heights([30, 30, 30])).image
        let b = OverviewGlyph(heights: OverviewGlyph.heights([31, 30, 30])).image
        let c = OverviewGlyph(heights: OverviewGlyph.heights([60, 30, 30])).image
        let wide = OverviewGlyph(heights: OverviewGlyph.heights([30, 30, 30, 30])).image
        #expect(a === b)
        #expect(a !== c)
        #expect(a.isTemplate)
        #expect(a.size == OverviewGlyph.size(bars: 3))
        #expect(wide.size == OverviewGlyph.size(bars: 4))
    }

    @Test func eachBarFollowsItsStat() {
        let r = OverviewItem.sampleModel().reading
        let metrics: [OverviewMetric] = [.cpu, .gpu, .memory, .disk, .hottest, .battery]
        // 29%, 100%, 49%, 58% used, 72 °C, 34%.
        #expect(OverviewLabel.heights(metrics, r) == [4, 14, 7, 8, 10, 5])
        #expect(OverviewLabel.heights([.network, .systemPower], r) == [0, 0], "no scale to fill towards")
    }

    @Test func voiceOverReadsTheChosenStats() {
        let r = OverviewItem.sampleModel().reading
        #expect(OverviewLabel.accessibilityText([.cpu, .disk, .hottest], r) == "Overview, CPU 29%, Disk 58% used, Hottest 72°C")
        #expect(OverviewLabel.accessibilityText([.battery], r) == "Overview, Battery 34%")
    }
}

@MainActor
struct OverviewGlyphSettingsTests {
    @Test func defaultsToCPUGPUAndMemory() {
        let s = AppSettings(defaults: TestDefaults().defaults)
        #expect(s.overviewGlyphMetrics == [.cpu, .gpu, .memory])
        #expect(s.overviewGlyphOrder == OverviewMetric.glyphChoices)
        #expect(!s.overviewGlyphOrder.contains(.network))
        #expect(!s.overviewGlyphOrder.contains(.systemPower))
    }

    @Test func choiceAndOrderPersist() {
        let suite = TestDefaults()
        let s = AppSettings(defaults: suite.defaults)
        s.setGlyphMetricShown(.hottest, true)
        s.setGlyphMetricShown(.gpu, false)
        s.moveOverviewGlyphMetric(.hottest, onto: .cpu)
        #expect(s.overviewGlyphMetrics == [.hottest, .cpu, .memory])
        let again = AppSettings(defaults: suite.defaults)
        #expect(again.overviewGlyphMetrics == [.hottest, .cpu, .memory])
    }

    @Test func keepsOneToSixBars() {
        let s = AppSettings(defaults: TestDefaults().defaults)
        s.setGlyphMetricShown(.gpu, false)
        s.setGlyphMetricShown(.memory, false)
        #expect(!s.canToggleGlyphMetric(.cpu))
        s.setGlyphMetricShown(.cpu, false)
        #expect(s.overviewGlyphMetrics == [.cpu])
        for m in OverviewMetric.glyphChoices { s.setGlyphMetricShown(m, true) }
        #expect(s.overviewGlyphMetrics.count == OverviewMetric.glyphLimit)
        #expect(s.overviewGlyphMetrics == Array(OverviewMetric.glyphChoices.prefix(6)))
        #expect(!s.canToggleGlyphMetric(.battery))
        #expect(s.canToggleGlyphMetric(.cpu))
        #expect(!s.canToggleGlyphMetric(.network))
    }

    @Test func garbageInDefaultsFallsBack() {
        let suite = TestDefaults()
        suite.defaults.set(["network", "bogus"], forKey: "overview.glyph.shown")
        suite.defaults.set(["battery", "battery", "systemPower"], forKey: "overview.glyph.order")
        let s = AppSettings(defaults: suite.defaults)
        #expect(s.overviewGlyphMetrics == [.cpu, .gpu, .memory])
        #expect(s.overviewGlyphOrder.first == .battery)
        #expect(s.overviewGlyphOrder.count == OverviewMetric.glyphChoices.count)
        let crowded = TestDefaults()
        crowded.defaults.set(OverviewMetric.glyphChoices.map(\.rawValue), forKey: "overview.glyph.shown")
        #expect(AppSettings(defaults: crowded.defaults).overviewGlyphMetrics.count == 6)
    }

    @Test func sourcesAreTheItemsTheBarsCopy() {
        #expect(OverviewItem.sources(for: [.cpu, .gpu, .memory]) == [.cpu, .gpu, .memory])
        #expect(OverviewItem.sources(for: [.cpuTemp, .hottest, .disk, .battery]) == [.temps, .disk])
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
        // 75% of 14 pt is 10.5, so 11; 40% is 5.6, so 6; 50% is 7.
        #expect(OverviewLabel.heights(s.overviewGlyphMetrics, item.model.reading) == [11, 6, 7])
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

    @Test func feedsWhatTheChosenBarsNeedAndNothingElse() {
        let rig = Rig()
        let s = rig.ctx.settings
        for id in ItemID.allCases { s.setShown(id, id == .overview) }
        s.setGlyphMetricShown(.hottest, true)
        s.setGlyphMetricShown(.battery, true)
        for m in [OverviewMetric.cpu, .gpu, .memory] { s.setGlyphMetricShown(m, false) }
        #expect(s.overviewGlyphMetrics == [.hottest, .battery])
        for i in 0..<3 { rig.ctx.scheduler.fire(now: .now.addingTimeInterval(Double(i) * 2)) }
        #expect(rig.temperatureReads == 3)
        #expect(rig.batteryReads == 3)
        #expect(rig.gpuReads == 0, "no GPU bar, no panel")
        #expect(rig.feed.reads == 0)
        let item = rig.overview!
        // Hottest of 58 and 54 °C fills 58% of 14 pt; 34% charge fills 5.
        #expect(OverviewLabel.heights(s.overviewGlyphMetrics, item.model.reading) == [8, 5])
        #expect(item.model.sparks[.hottest]?.count == 3)
        #expect(item.model.sparks[.cpu] == nil, "CPU wasn't read, so it gets no samples")
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
