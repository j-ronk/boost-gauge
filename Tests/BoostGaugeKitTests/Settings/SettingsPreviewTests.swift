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

    @Test func panelScalesDownToFitButNeverUp() {
        #expect(ScaledToFit<EmptyView>.scale(natural: CGSize(width: 300, height: 1000), available: CGSize(width: 320, height: 500)) == 0.5)
        #expect(ScaledToFit<EmptyView>.scale(natural: CGSize(width: 300, height: 200), available: CGSize(width: 320, height: 500)) == 1)
        #expect(ScaledToFit<EmptyView>.scale(natural: .zero, available: CGSize(width: 320, height: 500)) == 1)
    }
}
