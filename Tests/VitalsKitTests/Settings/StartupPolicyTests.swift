import AppKit
import Testing
@testable import VitalsKit

struct StartupPolicyTests {
    @Test func allHiddenOpensSettingsOnLaunch() {
        #expect(StartupPolicy.onLaunch(allHidden: true) == .openSettings)
    }

    @Test func someShownDoesNothingOnLaunch() {
        #expect(StartupPolicy.onLaunch(allHidden: false) == StartupAction.none)
    }

    @Test func reopenAlwaysOpensSettings() {
        #expect(StartupPolicy.onReopen() == .openSettings)
    }
}

@MainActor
struct SettingsOpenerTests {
    @Test func findsAppMenuItemByCommandComma() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About", action: nil, keyEquivalent: "")
        let settings = appMenu.addItem(withTitle: "Réglages…", action: nil, keyEquivalent: ",")
        let top = main.addItem(withTitle: "Vitals", action: nil, keyEquivalent: "")
        top.submenu = appMenu
        #expect(SettingsOpener.settingsMenuItem(in: main) === settings)
        #expect(SettingsOpener.settingsMenuItem(in: NSMenu()) == nil)
        #expect(SettingsOpener.settingsMenuItem(in: nil) == nil)
    }
}
