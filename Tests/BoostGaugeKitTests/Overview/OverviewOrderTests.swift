import Foundation
import Testing
@testable import BoostGaugeKit

@MainActor
struct OverviewOrderTests {
    @Test func defaultOrderIsTheBarsMockup() {
        let settings = AppSettings(defaults: TestDefaults().defaults)
        #expect(settings.overviewOrder == OverviewMetric.allCases)
        #expect(settings.overviewMetrics(for: .bars) == [.cpu, .gpu, .memory, .disk, .cpuTemp, .gpuTemp, .batteryTemp,
                                                         .battery, .systemPower, .network])
        #expect(settings.overviewMetrics(for: .list) == [.cpu, .gpu, .memory, .disk, .hottest, .battery, .network])
        #expect(settings.overviewMetrics(for: .tiles) == settings.overviewMetrics(for: .list))
    }

    @Test func storedOrderIsCleanedUp() {
        #expect(OverviewOrder.normalized(["network", "bogus", "cpu", "network"]).prefix(3) == [.network, .cpu, .gpu])
        #expect(OverviewOrder.normalized(nil) == OverviewMetric.allCases)
        #expect(Set(OverviewOrder.normalized(["disk"])) == Set(OverviewMetric.allCases))
    }

    @Test func orderAndVisibilityPersist() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.moveOverviewMetric(.network, onto: .cpu)
        settings.setOverviewMetricShown(.disk, false)
        let reopened = AppSettings(defaults: suite.reopen())
        #expect(reopened.overviewOrder.prefix(2) == [.network, .cpu])
        #expect(!reopened.isOverviewMetricShown(.disk))
        #expect(!reopened.overviewMetrics(for: .tiles).contains(.disk))
        #expect(reopened.overviewMetrics(for: .tiles).first == .network)
    }

    @Test func noOpWritesStoreNothing() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.overviewOrder = OverviewMetric.allCases
        settings.setOverviewMetricShown(.cpu, true)
        settings.moveOverviewMetric(.cpu, onto: .cpu)
        #expect(suite.defaults.object(forKey: "overview.order") == nil)
        #expect(suite.defaults.object(forKey: "overview.hidden") == nil)
    }

    @Test func liveMoveTakesTheTargetsPlaceInEitherDirection() {
        let settings = AppSettings(defaults: TestDefaults().defaults)
        settings.moveOverviewMetric(.cpu, onto: .memory)
        #expect(settings.overviewOrder.prefix(3) == [.gpu, .memory, .cpu])
        settings.moveOverviewMetric(.cpu, onto: .gpu)
        #expect(settings.overviewOrder.prefix(3) == [.cpu, .gpu, .memory])
    }

    @Test func barsKeepsHeadingsUntilAGroupIsSplit() {
        let bars = OverviewStyle.bars.metrics
        #expect(OverviewOrder.isGrouped(bars))
        #expect(OverviewOrder.sections(bars) == [[.cpu, .gpu, .memory, .disk], [.cpuTemp, .gpuTemp, .batteryTemp],
                                                 [.battery, .systemPower, .network]])
        // Whole groups can move about.
        let powerFirst: [OverviewMetric] = [.battery, .network, .cpu, .gpu]
        #expect(OverviewOrder.sections(powerFirst) == [[.battery, .network], [.cpu, .gpu]])
        // A temperature between two usage rows splits Usage: one plain list, in order.
        let split: [OverviewMetric] = [.cpu, .cpuTemp, .gpu]
        #expect(!OverviewOrder.isGrouped(split))
        #expect(OverviewOrder.sections(split) == [split])
        #expect(OverviewOrder.sections([]) == [])
    }

    @Test func tilesPairUpWithNetworkOnItsOwnRow() {
        #expect(OverviewOrder.tileRows(OverviewStyle.tiles.metrics) == [[.cpu, .gpu], [.memory, .disk], [.hottest, .battery], [.network]])
        #expect(OverviewOrder.tileRows([.cpu, .gpu, .network, .memory]) == [[.cpu, .gpu], [.network], [.memory]])
        // A tile stranded before Network keeps half a row.
        #expect(OverviewOrder.tileRows([.cpu, .network, .gpu, .memory]) == [[.cpu], [.network], [.gpu, .memory]])
    }
}

@MainActor
struct OverviewReorderTests {
    private let frames: [OverviewMetric: CGRect] = [
        .cpu: CGRect(x: 0, y: 0, width: 100, height: 20),
        .gpu: CGRect(x: 0, y: 26, width: 100, height: 20),
        .memory: CGRect(x: 0, y: 52, width: 100, height: 20),
    ]

    @Test func targetIsTheRowUnderThePointerButNeverTheDraggedOne() {
        #expect(ReorderTracker.target(at: CGPoint(x: 10, y: 30), in: frames, excluding: .cpu) == .gpu)
        #expect(ReorderTracker.target(at: CGPoint(x: 10, y: 5), in: frames, excluding: .cpu) == nil)
        #expect(ReorderTracker.target(at: CGPoint(x: 10, y: 23), in: frames, excluding: .cpu) == nil, "gap between rows")
    }

    @Test func onlyACommandDragReorders() {
        let tracker = ReorderTracker()
        tracker.frames = frames
        var moves: [(OverviewMetric, OverviewMetric)] = []
        tracker.changed(.cpu, at: CGPoint(x: 10, y: 30), commandDown: false) { moves.append(($0, $1)) }
        // Pressing Command partway through a plain drag doesn't turn it into a reorder.
        tracker.changed(.cpu, at: CGPoint(x: 10, y: 60), commandDown: true) { moves.append(($0, $1)) }
        #expect(moves.isEmpty)
        #expect(!tracker.suppressesTap)
        tracker.ended()

        tracker.changed(.cpu, at: CGPoint(x: 10, y: 30), commandDown: true) { moves.append(($0, $1)) }
        #expect(moves.count == 1 && moves[0] == (.cpu, .gpu))
        #expect(tracker.dragging == .cpu)
        #expect(tracker.suppressesTap, "the row the drag ends on mustn't also toggle")
        // Another row's gesture firing mid-drag isn't a second drag.
        tracker.changed(.memory, at: CGPoint(x: 10, y: 5), commandDown: true) { moves.append(($0, $1)) }
        #expect(moves.count == 1)
        tracker.ended()
        #expect(tracker.dragging == nil)
    }

    @Test func panelReorderWritesTheSettingsOrder() {
        let settings = AppSettings(defaults: TestDefaults().defaults)
        let tracker = ReorderTracker()
        tracker.frames = frames
        tracker.changed(.memory, at: CGPoint(x: 10, y: 5), commandDown: true) { settings.moveOverviewMetric($0, onto: $1) }
        #expect(settings.overviewOrder.prefix(3) == [.memory, .cpu, .gpu])
    }
}

@MainActor
struct OverviewSettingsPageTests {
    private func makeModel() -> (SettingsModel, AppContext) {
        let ctx = AppContext(settings: AppSettings(defaults: TestDefaults().defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        return (SettingsModel(ctx, loginItem: .inert), ctx)
    }

    @Test func listShowsTheStylesMetricsInTheSharedOrder() {
        let (model, ctx) = makeModel()
        #expect(model.overviewMetrics == OverviewStyle.bars.metrics)
        model.overviewStyle.wrappedValue = .tiles
        #expect(model.overviewMetrics == OverviewStyle.tiles.metrics)
        // A hidden metric stays in the list, switched off.
        model.metricShown(.disk).wrappedValue = false
        #expect(model.overviewMetrics.contains(.disk))
        #expect(!ctx.settings.overviewMetrics(for: .tiles).contains(.disk))
    }

    @Test func moveUpAndDownSkipMetricsTheStyleDoesntShow() {
        let (model, ctx) = makeModel()
        model.overviewStyle.wrappedValue = .tiles
        // In Tiles, Hottest follows Disk; Bars' CPU and GPU temperatures sit between them in the shared order.
        #expect(model.canMoveMetric(.hottest, by: -1))
        model.moveMetric(.hottest, by: -1)
        #expect(model.overviewMetrics.prefix(5) == [.cpu, .gpu, .memory, .hottest, .disk])
        #expect(ctx.settings.overviewOrder.firstIndex(of: .hottest)! < ctx.settings.overviewOrder.firstIndex(of: .disk)!)
        #expect(!model.canMoveMetric(.cpu, by: -1))
        #expect(!model.canMoveMetric(.network, by: 1))
    }

    /// What the Contents list's onMove calls: offsets count the style's metrics only.
    @Test func draggingAContentsRowKeepsOtherStylesMetricsInPlace() {
        let (model, ctx) = makeModel()
        model.overviewStyle.wrappedValue = .tiles
        let bars = ctx.settings.overviewOrder.filter { !OverviewStyle.tiles.metrics.contains($0) }
        // Network, last of seven, dragged to the top.
        model.moveMetrics(fromOffsets: IndexSet(integer: 6), toOffset: 0)
        #expect(model.overviewMetrics == [.network, .cpu, .gpu, .memory, .disk, .hottest, .battery])
        #expect(ctx.settings.overviewOrder.filter { !OverviewStyle.tiles.metrics.contains($0) } == bars)
        #expect(ctx.settings.overviewOrder.first == .network)
    }

    @Test func draggingAGlyphRowMovesItsBar() {
        let (model, ctx) = makeModel()
        // Memory (third) dragged to the front.
        model.moveGlyphMetrics(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(ctx.settings.overviewGlyphMetrics == [.memory, .cpu, .gpu])
        #expect(model.canMoveGlyphMetric(.memory, by: 1))
        #expect(!model.canMoveGlyphMetric(.memory, by: -1))
        model.moveGlyphMetric(.memory, by: 1)
        #expect(ctx.settings.overviewGlyphMetrics == [.cpu, .memory, .gpu])
    }
}
