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

    @Test func menuBarStripFollowsOrderVisibilityAndHideOthers() {
        let (model, ctx, _) = makeModel()
        #expect(model.menuBarItems == [.battery, .cpu, .memory])
        model.drop(.memory, onto: .cpu)
        #expect(model.menuBarItems == [.battery, .memory, .cpu])
        model.shown(.overview).wrappedValue = true
        #expect(model.menuBarItems.first == .overview)
        ctx.settings.overviewHidesOthers = true
        #expect(model.menuBarItems == [.overview])
    }

    @Test func previewTicksOnlyWhatNothingElseTicks() {
        let (model, ctx, _) = makeModel()
        #expect(!model.previewNeedsTicks(.cpu), "the scheduler ticks it")
        #expect(model.previewNeedsTicks(.gpu))
        ctx.settings.setShown(.overview, true)
        #expect(!model.previewNeedsTicks(.gpu), "Overview feeds its glyph's sources")
        #expect(model.previewNeedsTicks(.temps))
        ctx.settings.overviewHidesOthers = true
        #expect(!model.previewNeedsTicks(.cpu), "fed by Overview while it stands aside")
        #expect(model.previewNeedsTicks(.battery))
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
