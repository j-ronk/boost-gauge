import Foundation
import SwiftUI
import Testing
@testable import BoostGaugeKit

@MainActor
struct SettingsPreviewTests {
    private func makeModel() -> (SettingsModel, AppContext, [ItemID: FakeItem]) {
        let ctx = AppContext(settings: AppSettings(defaults: TestDefaults().defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        var items: [ItemID: FakeItem] = [:]
        for id in ItemID.allCases {
            let item = FakeItem(id)
            items[id] = item
            ctx.scheduler.register(item)
        }
        return (SettingsModel(ctx, loginItem: .inert), ctx, items)
    }

    @Test func menuBarStripFollowsOrderAndVisibility() {
        let (model, _, _) = makeModel()
        #expect(model.menuBarItems == [.battery, .cpu, .memory])
        model.move(.memory, by: -1)
        model.move(.memory, by: -1)
        #expect(model.menuBarItems == [.battery, .memory, .cpu])
        model.shown(.overview).wrappedValue = true
        #expect(model.menuBarItems == [.overview, .battery, .memory, .cpu])
        model.shown(.battery).wrappedValue = false
        #expect(model.menuBarItems == [.overview, .memory, .cpu])
    }

    @Test func previewTicksOnlyWhatNothingElseTicks() {
        let (model, ctx, _) = makeModel()
        #expect(!model.previewNeedsTicks(.cpu), "the scheduler ticks it")
        #expect(model.previewNeedsTicks(.gpu))
        ctx.settings.setShown(.overview, true)
        #expect(!model.previewNeedsTicks(.gpu), "Overview feeds its glyph's sources")
        #expect(model.previewNeedsTicks(.temps))
        ctx.settings.setGlyphMetricShown(.hottest, true)
        #expect(!model.previewNeedsTicks(.temps), "a temperature bar makes Overview feed Temps")
        #expect(model.previewNeedsTicks(.disk))
    }

    @Test func previewSamplesUntilItsPageGoes() async throws {
        let (model, _, items) = makeModel()
        let task = Task { await model.samplePreview(.gpu) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(items[.gpu]!.ticks == 1)
        task.cancel()
        await task.value
        #expect(items[.gpu]!.ticks == 1)
    }

    @Test func previewOpensThePanelThroughPresence() {
        let (model, ctx, _) = makeModel()
        model.previewOpened(.cpu)
        #expect(ctx.panels.isOpen(.cpu))
        model.previewClosed(.cpu)
        #expect(!ctx.panels.isOpen(.cpu))
    }

    /// The preview holds the panel open only while its task runs: closing the window cancels it, and the panel closes
    /// with it rather than ticking on behind a closed window.
    @Test func runningPreviewHoldsThePanelUntilCancelled() async throws {
        let (model, ctx, items) = makeModel()
        let task = Task { await model.runPreview(.gpu) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(ctx.panels.isOpen(.gpu))
        #expect(items[.gpu]!.ticks == 1)
        task.cancel()
        await task.value
        #expect(!ctx.panels.isOpen(.gpu))
        try await Task.sleep(for: .milliseconds(50))
        #expect(items[.gpu]!.ticks == 1)
    }

    @Test func tallPanelShowsItsTopAtFullSizeAndShortPanelShowsWhole() {
        typealias Top = PanelTop<EmptyView>
        #expect(Top.visibleHeight(natural: 1000) == Top.maxHeight)
        #expect(Top.isClipped(natural: 1000))
        #expect(Top.visibleHeight(natural: 200) == 200)
        #expect(!Top.isClipped(natural: 200))
        #expect(Top.visibleHeight(natural: Top.maxHeight) == Top.maxHeight)
        #expect(!Top.isClipped(natural: Top.maxHeight))
        #expect(Top.maxHeight == 320)
    }
}
