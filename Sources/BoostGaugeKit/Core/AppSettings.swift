import Foundation
import Observation

public enum TemperatureUnit: String, CaseIterable, Sendable { case celsius, fahrenheit }
public enum NetworkUnit: String, CaseIterable, Sendable { case bytes, bits }
public enum CaptionAlignment: String, CaseIterable, Sendable { case center, leading }

@MainActor @Observable public final class AppSettings {
    public static let allowedRefreshSeconds = [1, 2, 5, 10]
    public static let defaultRefreshSeconds = 2

    @ObservationIgnored let defaults: UserDefaults
    // Mirrors of the stored values so SwiftUI observes changes; UserDefaults itself isn't observable.
    private var shown: Set<ItemID>
    private var storedRefreshSeconds: Int
    private var storedShowBatteryPercentage: Bool
    private var storedTemperatureUnit: TemperatureUnit
    private var storedNetworkUnit: NetworkUnit
    private var storedCaptionAlignment: CaptionAlignment
    private var storedItemOrder: [ItemID]
    private var hiddenSections: Set<PanelSectionID>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shown = Set(ItemID.allCases.filter { id in
            defaults.object(forKey: Self.shownKey(id)) as? Bool ?? ItemDefaults.shown.contains(id)
        })
        storedRefreshSeconds = Self.validRefresh(defaults.object(forKey: Keys.refreshSeconds) as? Int)
        storedShowBatteryPercentage = defaults.object(forKey: Keys.showBatteryPercentage) as? Bool ?? true
        storedTemperatureUnit = defaults.string(forKey: Keys.temperatureUnit).flatMap(TemperatureUnit.init) ?? .celsius
        storedNetworkUnit = defaults.string(forKey: Keys.networkUnit).flatMap(NetworkUnit.init) ?? .bytes
        storedCaptionAlignment = defaults.string(forKey: Keys.captionAlignment).flatMap(CaptionAlignment.init) ?? .center
        storedItemOrder = ItemOrder.normalized(defaults.stringArray(forKey: Keys.itemOrder))
        // Sections are on unless turned off, so settings saved before section toggles existed show everything.
        hiddenSections = Set(PanelSectionID.allCases.filter { defaults.object(forKey: Self.sectionKey($0)) as? Bool == false })
    }

    public func isSectionShown(_ section: PanelSectionID) -> Bool { !hiddenSections.contains(section) }

    public func setSectionShown(_ section: PanelSectionID, _ isShown: Bool) {
        guard isShown != isSectionShown(section) else { return }
        if isShown { hiddenSections.remove(section) } else { hiddenSections.insert(section) }
        defaults.set(isShown, forKey: Self.sectionKey(section))
    }

    public func isShown(_ id: ItemID) -> Bool { shown.contains(id) }

    /// No-op when unchanged: the menu bar echoes every visibility set back here, and a write that still
    /// notified would make the scene set visibility again, forever.
    public func setShown(_ id: ItemID, _ isShown: Bool) {
        guard isShown != self.isShown(id) else { return }
        if isShown { shown.insert(id) } else { shown.remove(id) }
        defaults.set(isShown, forKey: Self.shownKey(id))
    }

    public var allHidden: Bool { shown.isEmpty }

    public var refreshSeconds: Int {
        get { storedRefreshSeconds }
        set {
            storedRefreshSeconds = Self.validRefresh(newValue)
            defaults.set(storedRefreshSeconds, forKey: Keys.refreshSeconds)
        }
    }

    public var showBatteryPercentage: Bool {
        get { storedShowBatteryPercentage }
        set {
            storedShowBatteryPercentage = newValue
            defaults.set(newValue, forKey: Keys.showBatteryPercentage)
        }
    }

    public var temperatureUnit: TemperatureUnit {
        get { storedTemperatureUnit }
        set { storedTemperatureUnit = newValue; defaults.set(newValue.rawValue, forKey: Keys.temperatureUnit) }
    }

    public var networkUnit: NetworkUnit {
        get { storedNetworkUnit }
        set { storedNetworkUnit = newValue; defaults.set(newValue.rawValue, forKey: Keys.networkUnit) }
    }

    public var captionAlignment: CaptionAlignment {
        get { storedCaptionAlignment }
        set { storedCaptionAlignment = newValue; defaults.set(newValue.rawValue, forKey: Keys.captionAlignment) }
    }

    /// Left to right in the menu bar. Always holds every item exactly once.
    public var itemOrder: [ItemID] {
        get { storedItemOrder }
        set {
            storedItemOrder = ItemOrder.normalized(newValue)
            defaults.set(storedItemOrder.map(\.rawValue), forKey: Keys.itemOrder)
        }
    }

    private enum Keys {
        static let refreshSeconds = "refreshSeconds"
        static let showBatteryPercentage = "battery.showPercentage"
        static let temperatureUnit = "temperatureUnit"
        static let networkUnit = "networkUnit"
        static let captionAlignment = "label.captionAlignment"
        static let itemOrder = "item.order"
    }

    private static func shownKey(_ id: ItemID) -> String { "item.\(id.rawValue).shown" }

    static func sectionKey(_ section: PanelSectionID) -> String { "panel.\(section.rawValue).shown" }

    private static func validRefresh(_ value: Int?) -> Int {
        guard let value, allowedRefreshSeconds.contains(value) else { return defaultRefreshSeconds }
        return value
    }
}
