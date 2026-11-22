import Foundation
import Testing
@testable import VitalsKit

@MainActor
struct TempsItemTests {
    private func context(_ suite: TestDefaults) -> AppContext {
        AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
    }

    @Test func hiddenItemReadsNothing() {
        let suite = TestDefaults()
        let ctx = context(suite)
        var reads = 0, fanReads = 0
        let item = TempsItem(ctx, readTemperatures: { reads += 1; return [("Tp01", 60)] },
                             readFans: { fanReads += 1; return [] })
        ctx.scheduler.register(item)
        #expect(!ctx.settings.isShown(.temps))
        ctx.scheduler.fire(now: .now)
        #expect(reads == 0)
        #expect(fanReads == 0)

        ctx.settings.setShown(.temps, true)
        ctx.scheduler.fire(now: .now)
        #expect(reads == 1)
        #expect(fanReads == 0)
    }

    @Test func labelHonoursUnit() {
        let suite = TestDefaults()
        let ctx = context(suite)
        let item = TempsItem(ctx, readTemperatures: { [("Tp01", 62.2), ("Tg05", 50)] }, readFans: { [] })
        #expect(item.labelValue == "—")
        item.tick(now: .now)
        #expect(item.labelValue == "62°C")
        ctx.settings.temperatureUnit = .fahrenheit
        #expect(item.labelValue == "144°F")
        #expect(item.labelWidest == "212°F")
    }

    @Test func fansReadOnlyOnPanelRefresh() {
        let suite = TestDefaults()
        let ctx = context(suite)
        var fanReads = 0
        let item = TempsItem(ctx, readTemperatures: { [] },
                             readFans: { fanReads += 1; return [FanReading(index: 0, rpm: 2317, min: 1200, max: 5700)] })
        item.tick(now: .now)
        #expect(fanReads == 0)
        item.refreshPanel()
        #expect(fanReads == 1)
        #expect(item.fans.map(\.rpm) == [2317])
    }
}
