import Foundation
import Observation
import SwiftUI

/// Shared state each track plugs into from `Registry`. Optional features stay nil until their slot is filled.
@MainActor @Observable public final class AppContext {
    public let settings: AppSettings
    public let scheduler: Scheduler
    public let powerSource: PowerSourceMonitor
    public let slots: MenuBarSlots
    public var energyMode: (any EnergyModeService)?
    public var settingsView: AnyView = AnyView(Text("Vitals").padding())
    public var onLaunch: (() -> Void)?
    public var onReopen: (() -> Void)?

    public init(settings: AppSettings, powerSource: PowerSourceMonitor) {
        self.settings = settings
        self.scheduler = Scheduler(settings: settings)
        self.powerSource = powerSource
        self.slots = MenuBarSlots(settings: settings)
    }

    public convenience init() {
        self.init(settings: AppSettings(), powerSource: PowerSourceMonitor())
    }
}
