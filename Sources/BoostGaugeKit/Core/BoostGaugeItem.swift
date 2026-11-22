import Foundation
import SwiftUI

@MainActor public protocol BoostGaugeItem: AnyObject {
    var id: ItemID { get }
    /// Menu bar label.
    var label: AnyView { get }
    /// The whole panel, already wrapped in `PanelChrome` by the item (the footer button is item-specific).
    var panel: AnyView { get }
    /// Menu bar refresh. The scheduler calls it only while the item is shown.
    func tick(now: Date)
    func panelDidOpen()
    func panelDidClose()
    /// Named states for `--render`. Items with fixtures add variants beside "live".
    func renderVariants() async -> [RenderVariant]
}

public extension BoostGaugeItem {
    func panelDidOpen() {}
    func panelDidClose() {}
    func renderVariants() async -> [RenderVariant] {
        [RenderVariant("live", label: label, panel: panel)]
    }
}

public struct RenderVariant {
    public let name: String
    public let label: AnyView
    public let panel: AnyView?

    public init(_ name: String, label: AnyView, panel: AnyView?) {
        self.name = name
        self.label = label
        self.panel = panel
    }
}
