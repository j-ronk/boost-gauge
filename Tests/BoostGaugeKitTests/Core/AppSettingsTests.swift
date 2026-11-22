import Foundation
import Observation
import Testing
@testable import BoostGaugeKit

@MainActor
struct AppSettingsTests {
    @Test func defaults() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        for id in ItemID.allCases {
            #expect(settings.isShown(id) == [.battery, .cpu, .memory].contains(id), "\(id)")
        }
        #expect(settings.refreshSeconds == 2)
        #expect(settings.showBatteryPercentage == true)
        #expect(settings.allHidden == false)
    }

    /// The MenuBarExtra isInserted binding echoes every isVisible set back through setShown. If an unchanged value
    /// still notified observers or wrote defaults, the scene re-applied isVisible and the echo looped at 100% CPU.
    @Test func settingTheSameShownValueChangesNothing() {
        final class Count: @unchecked Sendable { var value = 0 }
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.setShown(.gpu, true)
        let observed = Count()
        let writes = Count()
        withObservationTracking { _ = settings.isShown(.gpu) } onChange: { observed.value += 1 }
        let token = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: suite.defaults, queue: nil) { _ in writes.value += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.setShown(.gpu, true)
        settings.setShown(.disk, false)
        #expect(observed.value == 0)
        #expect(writes.value == 0)

        settings.setShown(.gpu, false)
        #expect(observed.value == 1)
        #expect(writes.value == 1)
        #expect(suite.defaults.object(forKey: "item.gpu.shown") as? Bool == false)
    }

    @Test func displayOptionsDefaultAndPersist() {
        let suite = TestDefaults()
        let first = AppSettings(defaults: suite.defaults)
        #expect(first.temperatureUnit == .celsius)
        #expect(first.networkUnit == .bytes)
        #expect(first.captionAlignment == .center)
        first.temperatureUnit = .fahrenheit
        first.networkUnit = .bits
        first.captionAlignment = .leading
        #expect(suite.defaults.string(forKey: "temperatureUnit") == "fahrenheit")
        let second = AppSettings(defaults: suite.reopen())
        #expect(second.temperatureUnit == .fahrenheit)
        #expect(second.networkUnit == .bits)
        #expect(second.captionAlignment == .leading)
    }

    @Test func persistsAcrossInstances() {
        let suite = TestDefaults()
        let first = AppSettings(defaults: suite.defaults)
        first.setShown(.gpu, true)
        first.setShown(.battery, false)
        first.refreshSeconds = 5
        first.showBatteryPercentage = false

        let second = AppSettings(defaults: suite.reopen())
        #expect(second.isShown(.gpu))
        #expect(!second.isShown(.battery))
        #expect(second.refreshSeconds == 5)
        #expect(second.showBatteryPercentage == false)
    }

    @Test func usesDocumentedKeys() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        settings.setShown(.temps, true)
        settings.refreshSeconds = 10
        settings.showBatteryPercentage = false
        #expect(suite.defaults.object(forKey: "item.temps.shown") as? Bool == true)
        #expect(suite.defaults.integer(forKey: "refreshSeconds") == 10)
        #expect(suite.defaults.object(forKey: "battery.showPercentage") as? Bool == false)
    }

    @Test func allHidden() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        for id in ItemID.allCases { settings.setShown(id, false) }
        #expect(settings.allHidden)
        settings.setShown(.power, true)
        #expect(!settings.allHidden)
    }

    @Test func invalidIntervalFallsBack() {
        let suite = TestDefaults()
        suite.defaults.set(7, forKey: "refreshSeconds")
        #expect(AppSettings(defaults: suite.defaults).refreshSeconds == 2)

        let settings = AppSettings(defaults: suite.defaults)
        settings.refreshSeconds = 3
        #expect(settings.refreshSeconds == 2)
        for allowed in [1, 2, 5, 10] {
            settings.refreshSeconds = allowed
            #expect(settings.refreshSeconds == allowed)
        }
    }
}
