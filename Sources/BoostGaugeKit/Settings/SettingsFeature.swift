import AppKit
import OSLog
import SwiftUI

public enum SettingsFeature {
    @MainActor public static func install(_ ctx: AppContext) {
        // A build-dir run would otherwise register that throwaway bundle in Login Items and use up the first run.
        let installed = Bundle.main.bundleURL.path.hasPrefix("/Applications/")
        install(ctx, defaults: .standard, loginItem: .system, firstRun: installed, open: SettingsOpener.open)
    }

    @MainActor static func install(_ ctx: AppContext, defaults: UserDefaults, loginItem: LoginItemControl,
                                   firstRun: Bool = true, open: @escaping @MainActor () -> Void) {
        if firstRun { LaunchAtLogin.configureOnFirstRun(defaults: defaults, control: loginItem) }
        ctx.settingsView = AnyView(SettingsView(model: SettingsModel(ctx, loginItem: loginItem)))
        ctx.onLaunch = { [weak ctx] in
            guard let ctx, StartupPolicy.onLaunch(allHidden: ctx.settings.allHidden) == .openSettings else { return }
            open()
        }
        ctx.onReopen = {
            if StartupPolicy.onReopen() == .openSettings { open() }
        }
    }
}

public extension SettingsFeature {
    /// Each Settings page for `--render`, named for the PNG.
    @MainActor static func renderPages(_ ctx: AppContext) -> [(name: String, view: AnyView)] {
        let model = SettingsModel(ctx)
        let panes: [(String, SettingsPane)] = [("general", .general), ("menubar", .menuBar)]
            + SettingsPane.items.map { (SettingsModel.title($0).lowercased(), .item($0)) }
        return panes.map { name, pane in (name, AnyView(SettingsView(model: model, pane: pane))) }
    }
}

/// SwiftUI only opens the Settings scene from `SettingsLink` or `openSettings` inside a view, and an accessory app
/// may have no view on screen at all. The app menu's Settings item is SwiftUI's own, and performing it works.
@MainActor enum SettingsOpener {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BoostGauge", category: "Settings")

    static func open() {
        // Scenes and the main menu aren't built yet when didFinishLaunching runs.
        DispatchQueue.main.async {
            NSApp.activate()
            if let item = settingsMenuItem(in: NSApp.mainMenu), let menu = item.menu {
                menu.performActionForItem(at: menu.index(of: item))
                log.info("opened Settings from the app menu")
            } else {
                log.error("no Settings menu item")
            }
        }
    }

    /// Found by its Cmd-, shortcut in the app menu: SwiftUI's action selector is private and the title is localised.
    static func settingsMenuItem(in mainMenu: NSMenu?) -> NSMenuItem? {
        mainMenu?.items.first?.submenu?.items.first {
            $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command
        }
    }
}
