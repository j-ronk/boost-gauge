import Foundation

/// A throwaway UserDefaults suite, so tests never read or write the app's real defaults domain.
///
/// Suites are removed when the test process exits, not in deinit: Swift may release a
/// local after its last use, while the code under test is still writing through its own
/// handle, and those late writes would bring the plist back.
final class TestDefaults {
    let name = "BoostGauge.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
        Self.register(name)
    }

    /// A second handle on the same suite, as a relaunched app would see it.
    func reopen() -> UserDefaults { UserDefaults(suiteName: name)! }

    var plistURL: URL { Self.plistURL(name) }

    /// Empties the suite and deletes its plist. removePersistentDomain alone leaves an
    /// empty plist behind, which still shows up in `defaults domains`.
    static func remove(_ name: String) {
        UserDefaults.standard.removePersistentDomain(forName: name)
        CFPreferencesAppSynchronize(name as CFString)
        try? FileManager.default.removeItem(at: plistURL(name))
    }

    private static func plistURL(_ name: String) -> URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences/\(name).plist")
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var names: Set<String> = []
    nonisolated(unsafe) private static var exitHookInstalled = false

    private static func register(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        names.insert(name)
        if !exitHookInstalled {
            exitHookInstalled = true
            atexit { TestDefaults.removeAll() }
        }
    }

    private static func removeAll() {
        lock.lock()
        let all = names
        names = []
        lock.unlock()
        all.forEach(remove)
    }
}
