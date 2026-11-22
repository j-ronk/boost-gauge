import SwiftUI

/// An item page's live preview: the item's menu bar label above its real panel, scaled down when the panel is
/// taller than the page. The panel is the menu bar's own view, so every Settings change shows as it's made.
struct ItemPreview: View {
    let model: SettingsModel
    let id: ItemID

    var body: some View {
        if let item = model.item(id) {
            VStack(spacing: 2) {
                MenuBarStrip { item.label }
                PanelTop {
                    item.panel
                        .allowsHitTesting(false)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Preview")
            .onAppear { model.previewOpened(id) }
            .onDisappear { model.previewClosed(id) }
            .task(id: id) { await model.samplePreview(id) }
        }
    }
}

/// The Menu Bar page's preview: the items in the menu bar, in order, as they sit there now.
struct MenuBarPreview: View {
    let model: SettingsModel

    var body: some View {
        MenuBarStrip {
            ForEach(model.menuBarItems, id: \.self) { id in
                model.item(id)?.label
            }
        }
        .animation(.snappy, value: model.menuBarItems)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu bar preview")
    }
}

/// A strip of menu bar, labels packed to the right as macOS packs status items.
struct MenuBarStrip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            content
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

/// The panel at its real size. One taller than `maxHeight` shows its top, fading out at the bottom: scaled down,
/// a tall panel's text gets too small to read.
struct PanelTop<Content: View>: View {
    static var maxHeight: CGFloat { 320 }
    static var fade: CGFloat { 56 }
    /// Room around the panel for its shadow, which a clip would otherwise cut.
    static var margin: CGFloat { 12 }

    @ViewBuilder let content: Content
    @State private var natural: CGFloat = 0

    static func visibleHeight(natural: CGFloat) -> CGFloat { min(natural, maxHeight) }
    static func isClipped(natural: CGFloat) -> Bool { natural > maxHeight }

    var body: some View {
        let clipped = Self.isClipped(natural: natural)
        let height = Self.visibleHeight(natural: natural) + Self.margin + (clipped ? 0 : Self.margin)
        content
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { natural = $0 }
            .padding(.horizontal, Self.margin)
            .padding(.top, Self.margin)
            .frame(height: height, alignment: .top)
            .mask {
                if clipped {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: 1 - Self.fade / height),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    Rectangle()
                }
            }
            .frame(maxWidth: .infinity)
    }
}
