import Foundation
import Observation

public enum TemperatureUnit: String, CaseIterable, Sendable { case celsius, fahrenheit }
public enum NetworkUnit: String, CaseIterable, Sendable { case bytes, bits }
public enum CaptionAlignment: String, CaseIterable, Sendable { case center, leading }
/// How the Overview panel lays out its readings. Raw values are stored, so never rename one.
public enum OverviewStyle: String, CaseIterable, Sendable { case bars, list, tiles }

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
    private var storedLargeValues: Bool
    private var storedItemOrder: [ItemID]
    private var hiddenSections: Set<PanelSectionID>
    private var storedOverviewStyle: OverviewStyle
    private var storedOverviewOrder: [OverviewMetric]
    private var hiddenOverviewMetrics: Set<OverviewMetric>
    private var storedGlyphOrder: [OverviewMetric]
    private var glyphShown: Set<OverviewMetric>

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
        storedLargeValues = defaults.bool(forKey: Keys.largeValues)
        storedItemOrder = ItemOrder.normalized(defaults.stringArray(forKey: Keys.itemOrder))
        // Sections are on unless turned off, so settings saved before section toggles existed show everything.
        hiddenSections = Set(PanelSectionID.allCases.filter { defaults.object(forKey: Self.sectionKey($0)) as? Bool == false })
        storedOverviewStyle = defaults.string(forKey: Keys.overviewStyle).flatMap(OverviewStyle.init) ?? .bars
        storedOverviewOrder = OverviewOrder.normalized(defaults.stringArray(forKey: Keys.overviewOrder))
        hiddenOverviewMetrics = Set((defaults.stringArray(forKey: Keys.overviewHidden) ?? []).compactMap(OverviewMetric.init))
        let glyphOrder = OverviewOrder.normalized(defaults.stringArray(forKey: Keys.overviewGlyphOrder), of: OverviewMetric.glyphChoices)
        storedGlyphOrder = glyphOrder
        let saved = Set((defaults.stringArray(forKey: Keys.overviewGlyphShown) ?? []).compactMap(OverviewMetric.init))
            .intersection(OverviewMetric.glyphChoices)
        glyphShown = Self.capped(saved.isEmpty ? Set(OverviewMetric.defaultGlyph) : saved, in: glyphOrder)
    }

    /// Keeps the first `glyphLimit` in order.
    private static func capped(_ chosen: Set<OverviewMetric>, in order: [OverviewMetric]) -> Set<OverviewMetric> {
        Set(order.filter(chosen.contains).prefix(OverviewMetric.glyphLimit))
    }

    /// Every stat the glyph can show, left to right, chosen or not.
    public var overviewGlyphOrder: [OverviewMetric] {
        get { storedGlyphOrder }
        set {
            let next = OverviewOrder.normalized(newValue.map(\.rawValue), of: OverviewMetric.glyphChoices)
            guard next != storedGlyphOrder else { return }
            storedGlyphOrder = next
            defaults.set(next.map(\.rawValue), forKey: Keys.overviewGlyphOrder)
        }
    }

    /// The glyph's bars, left to right: one to `glyphLimit` of them.
    public var overviewGlyphMetrics: [OverviewMetric] { storedGlyphOrder.filter(glyphShown.contains) }

    public func moveOverviewGlyphMetric(_ dragged: OverviewMetric, onto target: OverviewMetric) {
        overviewGlyphOrder = ItemOrder.live(dragged, onto: target, in: overviewGlyphOrder)
    }

    public func isGlyphMetricShown(_ metric: OverviewMetric) -> Bool { glyphShown.contains(metric) }

    /// False where the toggle would break the limits: the last bar can't go, and a seventh can't come.
    public func canToggleGlyphMetric(_ metric: OverviewMetric) -> Bool {
        guard OverviewMetric.glyphChoices.contains(metric) else { return false }
        return isGlyphMetricShown(metric) ? glyphShown.count > 1 : glyphShown.count < OverviewMetric.glyphLimit
    }

    public func setGlyphMetricShown(_ metric: OverviewMetric, _ isShown: Bool) {
        guard isShown != isGlyphMetricShown(metric), canToggleGlyphMetric(metric) else { return }
        if isShown { glyphShown.insert(metric) } else { glyphShown.remove(metric) }
        defaults.set(overviewGlyphMetrics.map(\.rawValue), forKey: Keys.overviewGlyphShown)
    }

    /// Top to bottom in every Overview style. Always holds every metric exactly once.
    public var overviewOrder: [OverviewMetric] {
        get { storedOverviewOrder }
        set {
            let next = OverviewOrder.normalized(newValue.map(\.rawValue))
            guard next != storedOverviewOrder else { return }
            storedOverviewOrder = next
            defaults.set(next.map(\.rawValue), forKey: Keys.overviewOrder)
        }
    }

    /// Live reorder, from the Settings list or a Cmd-drag in the panel: `dragged` takes `target`'s place.
    public func moveOverviewMetric(_ dragged: OverviewMetric, onto target: OverviewMetric) {
        overviewOrder = ItemOrder.live(dragged, onto: target, in: overviewOrder)
    }

    public func isOverviewMetricShown(_ metric: OverviewMetric) -> Bool { !hiddenOverviewMetrics.contains(metric) }

    public func setOverviewMetricShown(_ metric: OverviewMetric, _ isShown: Bool) {
        guard isShown != isOverviewMetricShown(metric) else { return }
        if isShown { hiddenOverviewMetrics.remove(metric) } else { hiddenOverviewMetrics.insert(metric) }
        defaults.set(hiddenOverviewMetrics.map(\.rawValue).sorted(), forKey: Keys.overviewHidden)
    }

    /// What a style shows, in order.
    public func overviewMetrics(for style: OverviewStyle) -> [OverviewMetric] {
        let allowed = Set(style.metrics)
        return overviewOrder.filter { allowed.contains($0) && isOverviewMetricShown($0) }
    }

    public var overviewStyle: OverviewStyle {
        get { storedOverviewStyle }
        set {
            guard newValue != storedOverviewStyle else { return }
            storedOverviewStyle = newValue
            defaults.set(newValue.rawValue, forKey: Keys.overviewStyle)
        }
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

    /// The last Settings page open, by its storage key.
    public var settingsPane: String? {
        get { defaults.string(forKey: Keys.settingsPane) }
        set {
            guard newValue != settingsPane else { return }
            defaults.set(newValue, forKey: Keys.settingsPane)
        }
    }

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

    /// Smaller captions over bigger values in the menu bar. Off keeps the original look.
    public var largeValues: Bool {
        get { storedLargeValues }
        set { storedLargeValues = newValue; defaults.set(newValue, forKey: Keys.largeValues) }
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
        static let largeValues = "label.largeValues"
        static let itemOrder = "item.order"
        static let overviewStyle = "overview.style"
        static let overviewOrder = "overview.order"
        static let overviewHidden = "overview.hidden"
        static let settingsPane = "settings.pane"
        static let overviewGlyphOrder = "overview.glyph.order"
        static let overviewGlyphShown = "overview.glyph.shown"
    }

    private static func shownKey(_ id: ItemID) -> String { "item.\(id.rawValue).shown" }

    static func sectionKey(_ section: PanelSectionID) -> String { "panel.\(section.rawValue).shown" }

    private static func validRefresh(_ value: Int?) -> Int {
        guard let value, allowedRefreshSeconds.contains(value) else { return defaultRefreshSeconds }
        return value
    }
}
