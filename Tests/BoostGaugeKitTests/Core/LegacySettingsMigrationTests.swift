import Foundation
import Testing
@testable import BoostGaugeKit

@MainActor
struct LegacySettingsMigrationTests {
    @Test func legacyDomainSwapsTheAppName() {
        #expect(LegacySettingsMigration.legacyDomain(forBundleID: "com.example.BoostGauge") == "com.example.Vitals")
        #expect(LegacySettingsMigration.legacyDomain(forBundleID: "com.example.BoostGauge.Helper") == nil)
        #expect(LegacySettingsMigration.legacyDomain(forBundleID: "com.apple.dt.xctest.tool") == nil)
        #expect(LegacySettingsMigration.legacyDomain(forBundleID: nil) == nil)
    }

    @Test func copiesKnownSettingsIntoAnEmptyDomain() {
        let old = TestDefaults(), new = TestDefaults()
        old.defaults.set(false, forKey: "item.battery.shown")
        old.defaults.set(true, forKey: "item.gpu.shown")
        old.defaults.set(["gpu", "cpu", "battery"], forKey: "item.order")
        old.defaults.set(5, forKey: "refreshSeconds")
        old.defaults.set(false, forKey: "battery.showPercentage")
        old.defaults.set("fahrenheit", forKey: "temperatureUnit")
        old.defaults.set("bits", forKey: "networkUnit")
        old.defaults.set("leading", forKey: "label.captionAlignment")
        old.defaults.set(1234.0, forKey: "NSStatusItem Preferred Position Item-0")
        old.defaults.set(true, forKey: "launchAtLogin.configured")
        old.defaults.set("x", forKey: "unrelated")

        let copied = LegacySettingsMigration.run(legacySuite: old.name, into: new.defaults, domain: new.name)

        #expect(copied.count == 9)
        let settings = AppSettings(defaults: new.reopen())
        #expect(!settings.isShown(.battery))
        #expect(settings.isShown(.gpu))
        #expect(Array(settings.itemOrder.prefix(3)) == [.gpu, .cpu, .battery])
        #expect(settings.refreshSeconds == 5)
        #expect(settings.showBatteryPercentage == false)
        #expect(settings.temperatureUnit == .fahrenheit)
        #expect(settings.networkUnit == .bits)
        #expect(settings.captionAlignment == .leading)
        #expect(new.defaults.double(forKey: "NSStatusItem Preferred Position Item-0") == 1234)
        // The new app is a new login item, so it must register itself on its own first run.
        #expect(new.defaults.object(forKey: "launchAtLogin.configured") == nil)
        #expect(new.defaults.object(forKey: "unrelated") == nil)
    }

    @Test func leavesAnAlreadyConfiguredDomainAlone() {
        let old = TestDefaults(), new = TestDefaults()
        old.defaults.set(10, forKey: "refreshSeconds")
        old.defaults.set(true, forKey: "item.gpu.shown")
        new.defaults.set(1, forKey: "refreshSeconds")

        #expect(LegacySettingsMigration.run(legacySuite: old.name, into: new.defaults, domain: new.name).isEmpty)
        #expect(new.defaults.integer(forKey: "refreshSeconds") == 1)
        #expect(new.defaults.object(forKey: "item.gpu.shown") == nil)
    }

    @Test func runsOnlyOnce() {
        let old = TestDefaults(), new = TestDefaults()
        old.defaults.set(5, forKey: "refreshSeconds")
        #expect(LegacySettingsMigration.run(legacySuite: old.name, into: new.defaults, domain: new.name) == ["refreshSeconds"])

        // The person resets a setting back to empty; a later launch must not bring the old value back.
        new.defaults.removeObject(forKey: "refreshSeconds")
        #expect(LegacySettingsMigration.run(legacySuite: old.name, into: new.defaults, domain: new.name).isEmpty)
        #expect(new.defaults.object(forKey: "refreshSeconds") == nil)
    }

    @Test func nothingToCopyWhenThereWasNoOldApp() {
        let old = TestDefaults(), new = TestDefaults()
        #expect(LegacySettingsMigration.run(legacySuite: old.name, into: new.defaults, domain: new.name).isEmpty)
        #expect(new.defaults.object(forKey: "refreshSeconds") == nil)
    }

    @Test func copiesBatteryHistoryWhenTheNewFileIsMissing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Vitals/battery-history.csv")
        let new = root.appendingPathComponent("BoostGauge/battery-history.csv")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "1800000000,40,1\n".write(to: old, atomically: true, encoding: .utf8)

        #expect(LegacySettingsMigration.copyHistory(from: old, to: new))
        #expect(try String(contentsOf: new, encoding: .utf8) == "1800000000,40,1\n")

        try "1800000060,41,1\n".write(to: old, atomically: true, encoding: .utf8)
        #expect(!LegacySettingsMigration.copyHistory(from: old, to: new))
        #expect(try String(contentsOf: new, encoding: .utf8) == "1800000000,40,1\n")
    }

    @Test func noHistoryToCopy() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-migration-\(UUID().uuidString)")
        let new = root.appendingPathComponent("BoostGauge/battery-history.csv")
        #expect(!LegacySettingsMigration.copyHistory(from: root.appendingPathComponent("Vitals/battery-history.csv"), to: new))
        #expect(!FileManager.default.fileExists(atPath: new.path))
    }
}
