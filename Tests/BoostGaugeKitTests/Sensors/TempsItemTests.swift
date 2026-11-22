import Foundation
import Testing
@testable import BoostGaugeKit

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

    private static let groups = [
        TempGroupReading(.cpu, (1...10).map { TempSensor("Core \($0)", 50 + Double($0)) }),
        TempGroupReading(.battery, [TempSensor("Battery 1", 33), TempSensor("Battery 2", 34)]),
        TempGroupReading(.wireless, [TempSensor("Wi-Fi", 45)]),
    ]

    @Test func groupsReadOnlyOnPanelRefreshAndSkipHiddenSections() {
        let suite = TestDefaults()
        let ctx = context(suite)
        var asked: [Set<TempGroup>] = []
        let item = TempsItem(ctx, readTemperatures: { [] }, readFans: { [] },
                             readGroups: { wanted in asked.append(wanted); return Self.groups.filter { wanted.contains($0.group) } })
        item.tick(now: .now)
        #expect(asked.isEmpty)
        item.refreshPanel()
        #expect(asked.last == Set(TempGroup.allCases))
        #expect(item.groups.map(\.group) == [.cpu, .battery, .wireless])

        ctx.settings.setSectionShown(.tempsCPU, false)
        item.refreshPanel()
        #expect(asked.last == Set(TempGroup.allCases).subtracting([.cpu]))
        #expect(item.groups.map(\.group) == [.battery, .wireless])

        for group in TempGroup.allCases { ctx.settings.setSectionShown(group.section, false) }
        let before = asked.count
        item.refreshPanel()
        #expect(asked.count == before)
        #expect(item.groups.isEmpty)
    }

    @Test func longGroupsStartCollapsedAndExpansionPersists() {
        let suite = TestDefaults()
        let ctx = context(suite)
        let item = TempsItem(ctx, readTemperatures: { [] }, readFans: { [] }, readGroups: { _ in Self.groups })
        let cpu = Self.groups[0], battery = Self.groups[1], wifi = Self.groups[2]
        #expect(!item.isExpanded(cpu))
        #expect(item.isExpanded(battery))
        #expect(item.isExpandable(cpu) && item.isExpandable(battery) && !item.isExpandable(wifi))

        item.toggleExpanded(cpu)
        item.toggleExpanded(battery)
        #expect(item.isExpanded(cpu) && !item.isExpanded(battery))

        // As a relaunched app would see it.
        let relaunched = TempsItem(AppContext(settings: AppSettings(defaults: suite.reopen()),
                                              powerSource: PowerSourceMonitor(initial: .adapter)),
                                   readTemperatures: { [] }, readFans: { [] })
        #expect(relaunched.isExpanded(cpu))
        #expect(!relaunched.isExpanded(battery))
    }

    @Test func sampleMatchesTheReadmeNumbers() {
        let s = TempsItem.sample
        func g(_ group: TempGroup) -> TempGroupReading { s.first { $0.group == group }! }
        #expect(g(.cpu).hottest?.celsius == 72)
        #expect(Int(g(.cpu).average!.rounded()) == 58)
        #expect(Int(g(.gpu).average!.rounded()) == 54)
        #expect(Int(g(.battery).average!.rounded()) == 35)
        #expect(s.flatMap(\.sensors).map(\.celsius).max() == 72)
        #expect(s.map(\.group) == TempGroup.allCases)
    }
}

