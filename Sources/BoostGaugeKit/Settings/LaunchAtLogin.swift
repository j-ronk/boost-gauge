import Foundation
import OSLog
import ServiceManagement

/// Seam over `SMAppService.mainApp` so tests never register the test host as a login item.
public struct LoginItemControl {
    public var isEnabled: @MainActor () -> Bool
    public var setEnabled: @MainActor (Bool) -> Void

    public init(isEnabled: @escaping @MainActor () -> Bool, setEnabled: @escaping @MainActor (Bool) -> Void) {
        self.isEnabled = isEnabled
        self.setEnabled = setEnabled
    }

    public static let system = LoginItemControl(isEnabled: { LaunchAtLogin.isEnabled },
                                                setEnabled: { LaunchAtLogin.isEnabled = $0 })
    static let inert = LoginItemControl(isEnabled: { false }, setEnabled: { _ in })
}

public enum LaunchAtLogin {
    static let configuredKey = "launchAtLogin.configured"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BoostGauge", category: "LaunchAtLogin")

    /// On by default, but only once: after that the user's choice in Settings or Login Items stands.
    public static func shouldRegisterOnFirstRun(alreadyConfigured: Bool) -> Bool { !alreadyConfigured }

    @MainActor public static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                log.error("launch at login \(newValue ? "register" : "unregister", privacy: .public) failed: \(error, privacy: .public)")
            }
        }
    }

    @MainActor static func configureOnFirstRun(defaults: UserDefaults, control: LoginItemControl) {
        guard shouldRegisterOnFirstRun(alreadyConfigured: defaults.bool(forKey: configuredKey)) else { return }
        control.setEnabled(true)
        defaults.set(true, forKey: configuredKey)
    }
}
