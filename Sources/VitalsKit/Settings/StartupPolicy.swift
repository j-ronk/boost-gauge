import Foundation

public enum StartupAction: Sendable { case none, openSettings }

public enum StartupPolicy {
    /// With nothing in the menu bar, Settings is the only way back in.
    public static func onLaunch(allHidden: Bool) -> StartupAction {
        allHidden ? .openSettings : .none
    }

    /// Always, because macOS can hide shown items for lack of menu bar space and that can't be detected.
    public static func onReopen() -> StartupAction { .openSettings }
}
