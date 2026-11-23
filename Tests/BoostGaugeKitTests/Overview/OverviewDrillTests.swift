import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import BoostGaugeKit

@MainActor
struct OverviewDrillTests {
    typealias Rig = OverviewItemTests.Rig

    @Test func everyMetricOpensItsItem() {
        let expected: [OverviewMetric: ItemID] = [
            .cpu: .cpu, .gpu: .gpu, .memory: .memory, .disk: .disk,
            .cpuTemp: .temps, .gpuTemp: .temps, .batteryTemp: .temps, .hottest: .temps,
            .battery: .battery, .systemPower: .power, .network: .network,
        ]
        for metric in OverviewMetric.allCases { #expect(metric.item == expected[metric], "\(metric)") }
        #expect(OverviewMetric.Group.temperatures.item == .temps)
        #expect(OverviewMetric.Group.power.item == .power)
        #expect(OverviewMetric.Group.usage.item == nil)
        #expect(OverviewDrillText.accessibilityLabel(.cpu) == "Show CPU details")
        #expect(OverviewDrillText.accessibilityLabel(.temps) == "Show Temperatures details")
    }

    @Test func openingAndGoingBackOpensAndClosesTheItemsPanel() {
        let rig = Rig()
        let nav = OverviewNavigator(host: rig.overview)
        nav.open(OverviewMetric.gpuTemp.item)
        #expect(nav.shown == .temps)
        #expect(rig.ctx.panels.isOpen(.temps))
        nav.back()
        #expect(nav.shown == nil)
        #expect(!rig.ctx.panels.isOpen(.temps))
        nav.back()
        #expect(!rig.ctx.panels.isOpen(.temps), "a second back is harmless")
    }

    @Test func switchingItemsClosesTheFirst() {
        let rig = Rig()
        let nav = OverviewNavigator(host: rig.overview)
        nav.open(.gpu)
        nav.open(.gpu)
        nav.open(.memory)
        #expect(!rig.ctx.panels.isOpen(.gpu))
        #expect(rig.ctx.panels.isOpen(.memory))
        nav.back()
        #expect(!rig.ctx.panels.isOpen(.memory))
    }

    @Test func overviewNeverDrillsIntoItself() {
        let rig = Rig()
        let nav = OverviewNavigator(host: rig.overview)
        nav.open(.overview)
        #expect(nav.shown == nil)
        #expect(rig.overview.panel(for: .overview) == nil)
        #expect(rig.overview.panel(for: .cpu) != nil)
    }

    @Test func drilledItemOutOfTheMenuBarIsTickedUntilBack() {
        let rig = Rig()
        let s = rig.ctx.settings
        for id in ItemID.allCases { s.setShown(id, id == .overview) }
        let power = FakeItem(.power)
        rig.ctx.scheduler.register(power)
        rig.overview.panelDidOpen()
        let nav = OverviewNavigator(host: rig.overview)
        nav.open(.power)
        #expect(power.ticks == 1, "read on open, not a beat later")
        rig.ctx.scheduler.fire(now: .now)
        #expect(power.ticks == 2)
        nav.back()
        rig.ctx.scheduler.fire(now: .now.addingTimeInterval(2))
        #expect(power.ticks == 2)
    }

    @Test func drillingIntoAPanelSourceDoesNotTickItTwice() {
        let rig = Rig()
        let s = rig.ctx.settings
        for id in ItemID.allCases { s.setShown(id, id == .overview) }
        rig.overview.panelDidOpen()
        let reads = rig.gpuReads
        let nav = OverviewNavigator(host: rig.overview)
        nav.open(.gpu)
        #expect(rig.gpuReads == reads, "the panel already reads GPU every beat")
        rig.ctx.scheduler.fire(now: .now)
        #expect(rig.gpuReads == reads + 1)
    }

    @Test func drilledItemInTheMenuBarIsLeftToTheScheduler() {
        let rig = Rig()
        let s = rig.ctx.settings
        for id in ItemID.allCases { s.setShown(id, id == .overview || id == .power) }
        let power = FakeItem(.power)
        rig.ctx.scheduler.register(power)
        let nav = OverviewNavigator(host: rig.overview)
        nav.open(.power)
        #expect(power.ticks == 0)
        rig.ctx.scheduler.fire(now: .now)
        #expect(power.ticks == 1)
    }

    @Test func openingThePanelNoLongerStartsProcessSampling() {
        let rig = Rig()
        rig.overview.panelDidOpen()
        #expect(!rig.ctx.panels.isOpen(.cpu), "only the List's open CPU row samples processes")
        rig.overview.processesShown(true)
        #expect(rig.ctx.panels.isOpen(.cpu))
        rig.overview.model.topProcesses = []
        rig.overview.processesShown(false)
        #expect(!rig.ctx.panels.isOpen(.cpu))
        #expect(rig.overview.model.topProcesses == nil)
        rig.overview.processesShown(false)
        #expect(!rig.ctx.panels.isOpen(.cpu), "an extra hide doesn't close someone else's panel")
    }

    @Test func processesAreNotSampledWhileHidden() async {
        let rig = Rig()
        await rig.overview.sampleProcesses()
        #expect(rig.overview.model.topProcesses == nil)
    }

    @Test func cmdDragNeverDrills() {
        let tracker = ReorderTracker()
        #expect(tracker.allowsDrill(commandDown: false))
        #expect(!tracker.allowsDrill(commandDown: true), "a Cmd-click is the start of a Cmd-drag")
        tracker.frames = [.cpu: CGRect(x: 0, y: 0, width: 100, height: 20), .gpu: CGRect(x: 0, y: 24, width: 100, height: 20)]
        tracker.changed(.cpu, at: CGPoint(x: 10, y: 30), commandDown: true) { _, _ in }
        #expect(!tracker.allowsDrill(commandDown: false), "mid-drag")
        tracker.ended()
        // The click that ends the drag lands in the same event, before the tracker clears.
        #expect(!tracker.allowsDrill(commandDown: false))
    }

    @Test func plainDragStillDrillsOnRelease() {
        let tracker = ReorderTracker()
        tracker.changed(.cpu, at: .zero, commandDown: false) { _, _ in }
        tracker.ended()
        #expect(tracker.allowsDrill(commandDown: false))
    }

    @Test func arrowKeysWalkTheMetricsInPanelOrder() {
        let highlight = RowHighlight()
        let metrics: [OverviewMetric] = [.network, .cpu, .gpu]
        highlight.step(1, in: metrics)
        #expect(highlight.metric == .network)
        highlight.step(1, in: metrics)
        highlight.step(1, in: metrics)
        highlight.step(1, in: metrics)
        #expect(highlight.metric == .gpu, "stops at the end")
        highlight.step(-1, in: metrics)
        #expect(highlight.metric == .cpu)
        let fromNothing = RowHighlight()
        fromNothing.step(-1, in: metrics)
        #expect(fromNothing.metric == .gpu)
        fromNothing.hover(.heading(.power), true)
        #expect(fromNothing.metric == nil)
        fromNothing.hover(.heading(.power), false)
        #expect(fromNothing.row == nil)
        fromNothing.hover(.metric(.cpu), true)
        fromNothing.hover(.metric(.gpu), false)
        #expect(fromNothing.metric == .cpu, "leaving another row keeps this one lit")
    }
}

@MainActor
struct OverviewFirstBeatTests {
    private func rig(settle: Duration? = .milliseconds(10)) -> (AppContext, OverviewItem, TestDefaults) {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let feed = TickFeed()
        ctx.scheduler.register(CPUItem(ctx, readTicks: feed.read, settleDelay: settle))
        ctx.scheduler.register(GPUItem(ctx, read: { 40 }))
        ctx.scheduler.register(MemoryItem(ctx, read: { MemoryStats(usedBytes: 8 << 30, totalBytes: 16 << 30, usedPercent: 50) }))
        ctx.scheduler.register(TempsItem(ctx, readTemperatures: { [("Tp01", 58), ("Tg05", 54)] }, readFans: { [] }))
        let overview = OverviewItem(ctx, readBattery: { _ in nil }, settleDelay: .milliseconds(40))
        ctx.scheduler.register(overview)
        for id in ItemID.allCases { ctx.settings.setShown(id, id == .overview) }
        return (ctx, overview, suite)
    }

    @Test func cpuSettlesWithinTheBeatAfterThePanelOpens() async throws {
        let (ctx, overview, _) = rig()
        ctx.settings.setGlyphMetricShown(.gpu, true)
        ctx.settings.setGlyphMetricShown(.cpu, false)
        try await Task.sleep(for: .milliseconds(20))
        overview.panelDidOpen()
        #expect(overview.model.reading.cpu == nil, "a fresh baseline has no value yet")
        try await Task.sleep(for: .milliseconds(150))
        #expect(overview.model.reading.cpu == 75)
    }

    @Test func aNewlyChosenBarFillsWithoutWaitingForTheBeat() async throws {
        let (ctx, overview, _) = rig()
        ctx.scheduler.fire(now: .now)
        #expect(overview.model.reading.temps.hottest == nil)
        ctx.settings.setGlyphMetricShown(.hottest, true)
        try await Task.sleep(for: .milliseconds(30))
        #expect(overview.model.reading.temps.hottest == 58)
        #expect(OverviewLabel.heights(ctx.settings.overviewGlyphMetrics, overview.model.reading).last == 8)
    }

    @Test func aNewCPUBarSettlesToo() async throws {
        let (ctx, overview, _) = rig()
        ctx.settings.setGlyphMetricShown(.cpu, false)
        try await Task.sleep(for: .milliseconds(20))
        ctx.scheduler.fire(now: .now)
        ctx.settings.setGlyphMetricShown(.cpu, true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(overview.model.reading.cpu == 75)
    }
}
