import Foundation

/// A throwaway UserDefaults suite, so tests never read or write the app's real defaults domain.
final class TestDefaults {
    let name = "Vitals.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    /// A second handle on the same suite, as a relaunched app would see it.
    func reopen() -> UserDefaults { UserDefaults(suiteName: name)! }

    deinit { defaults.removePersistentDomain(forName: name) }
}
