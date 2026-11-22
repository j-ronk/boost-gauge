import Foundation
import os

/// The app shipped as "Vitals" before it was renamed Boost Gauge. A new bundle ID means a new defaults domain
/// and a new Application Support folder, so the first launch under the new name copies the old ones across once.
public enum LegacySettingsMigration {
    static let legacyAppName = "Vitals"
    static let appName = "BoostGauge"
    static let doneKey = "migration.legacySettingsCopied"

    // launchAtLogin.configured stays behind: the renamed app is a new login item and has to register itself.
    static let exactKeys: Set<String> = ["refreshSeconds", "temperatureUnit", "networkUnit"]
    static let keyPrefixes = ["item.", "label.", "battery.", "NSStatusItem "]

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? appName, category: "Migration")

    /// "com.example.BoostGauge" gives "com.example.Vitals".
    public static func legacyDomain(forBundleID bundleID: String?) -> String? {
        guard let bundleID, bundleID.hasSuffix("." + appName) else { return nil }
        return String(bundleID.dropLast(appName.count)) + legacyAppName
    }

    static func isMigrated(_ key: String) -> Bool {
        exactKeys.contains(key) || keyPrefixes.contains { key.hasPrefix($0) }
    }

    /// Copies the old app's settings into `defaults` (whose own domain is `domain`) if that domain holds none
    /// of its own yet. Returns the keys copied. Only the domain itself is checked, not the global one.
    @discardableResult
    public static func run(legacySuite: String, into defaults: UserDefaults, domain: String) -> [String] {
        guard !defaults.bool(forKey: doneKey) else { return [] }
        let alreadySet = (defaults.persistentDomain(forName: domain) ?? [:]).keys.contains(where: isMigrated)
        defaults.set(true, forKey: doneKey)
        guard !alreadySet, let old = UserDefaults(suiteName: legacySuite)?.persistentDomain(forName: legacySuite) else { return [] }
        let copied = old.filter { isMigrated($0.key) }
        for (key, value) in copied { defaults.set(value, forKey: key) }
        return copied.keys.sorted()
    }

    /// Copies the battery history file unless the new one already exists. Returns whether it copied.
    @discardableResult
    public static func copyHistory(from old: URL, to new: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return false }
        do {
            try fm.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: old, to: new)
            return true
        } catch {
            log.error("battery history copy failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Called once at launch, before anything reads settings or battery history.
    public static func runAtLaunch() {
        if let domain = Bundle.main.bundleIdentifier, let legacy = legacyDomain(forBundleID: domain) {
            let copied = run(legacySuite: legacy, into: .standard, domain: domain)
            if !copied.isEmpty { log.info("copied \(copied.count) settings from the old app") }
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        copyHistory(from: support.appendingPathComponent(legacyAppName).appendingPathComponent(HistoryStore.fileName),
                    to: HistoryStore.defaultURL)
    }
}
