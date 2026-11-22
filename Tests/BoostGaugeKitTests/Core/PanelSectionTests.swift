import Foundation
import Observation
import Testing
@testable import BoostGaugeKit

@MainActor
struct PanelSectionTests {
    @Test func everySectionBelongsToAnItemAndEveryItemHasSections() {
        for section in PanelSectionID.allCases {
            #expect(section.rawValue.hasPrefix(section.item.rawValue + "."), "\(section)")
            #expect(!section.title.isEmpty)
        }
        for id in ItemID.allCases {
            #expect(!PanelSectionID.sections(of: id).isEmpty, "\(id)")
        }
    }

    @Test func toggleTitlesAreUniqueWithinAnItem() {
        for id in ItemID.allCases {
            let titles = PanelSectionID.sections(of: id).map(\.title)
            #expect(Set(titles).count == titles.count, "\(id): \(titles)")
        }
        #expect(PanelSectionID.sections(of: .cpu).map(\.title) == ["Cores Chart", "Details", "Top Processes"])
        #expect(PanelSectionID.sections(of: .battery).map(\.title)
            == ["Energy Mode", "History", "Power", "Power Chart", "Health", "Using Energy"])
    }

    @Test func freshSettingsShowEverySection() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        for section in PanelSectionID.allCases { #expect(settings.isSectionShown(section), "\(section)") }
    }

    /// Settings saved before section toggles existed have none of their keys; nothing may change for those users.
    @Test func settingsFromBeforeSectionTogglesKeepWorkingWithEverySectionOn() {
        let suite = TestDefaults()
        suite.defaults.set(false, forKey: "item.battery.shown")
        suite.defaults.set(true, forKey: "item.gpu.shown")
        suite.defaults.set(5, forKey: "refreshSeconds")
        suite.defaults.set(false, forKey: "battery.showPercentage")
        suite.defaults.set("fahrenheit", forKey: "temperatureUnit")
        suite.defaults.set(["gpu", "cpu"], forKey: "item.order")

        let settings = AppSettings(defaults: suite.reopen())
        #expect(!settings.isShown(.battery))
        #expect(settings.isShown(.gpu))
        #expect(settings.refreshSeconds == 5)
        #expect(!settings.showBatteryPercentage)
        #expect(settings.temperatureUnit == .fahrenheit)
        #expect(Array(settings.itemOrder.prefix(2)) == [.gpu, .cpu])
        for section in PanelSectionID.allCases { #expect(settings.isSectionShown(section), "\(section)") }
    }

    @Test func hiddenSectionsPersistAcrossRelaunch() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.setSectionShown(.cpuTopProcesses, false)
        settings.setSectionShown(.batteryUsingEnergy, false)
        settings.setSectionShown(.batteryUsingEnergy, true)

        let relaunched = AppSettings(defaults: suite.reopen())
        #expect(!relaunched.isSectionShown(.cpuTopProcesses))
        #expect(relaunched.isSectionShown(.batteryUsingEnergy))
        #expect(relaunched.isSectionShown(.cpuDetails))
        #expect(suite.defaults.object(forKey: "panel.cpu.topProcesses.shown") as? Bool == false)
    }

    @Test func togglingASectionNotifiesOnlyWhenItChanges() {
        final class Count: @unchecked Sendable { var value = 0 }
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        let observed = Count()
        withObservationTracking { _ = settings.isSectionShown(.gpuDetails) } onChange: { observed.value += 1 }

        settings.setSectionShown(.gpuDetails, true)
        #expect(observed.value == 0)
        #expect(suite.defaults.object(forKey: "panel.gpu.details.shown") == nil)

        settings.setSectionShown(.gpuDetails, false)
        #expect(observed.value == 1)
    }
}
