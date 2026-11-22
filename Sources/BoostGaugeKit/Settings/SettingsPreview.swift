import SwiftUI

/// An item page's live preview: the item's menu bar label above its real panel, scaled down when the panel is
/// taller than the page. The panel is the menu bar's own view, so every Settings change shows as it's made.
struct ItemPreview: View {
    let model: SettingsModel
    let id: ItemID

    var body: some View {
        if let item = model.item(id) {
            VStack(spacing: 14) {
                MenuBarStrip { item.label }
                ScaledToFit {
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

/// Lays the content out at its own size and scales it down, never up, to fit, keeping it centred at the top.
struct ScaledToFit<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var natural = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            content
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
                .scaleEffect(Self.scale(natural: natural, available: geo.size), anchor: .top)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    static func scale(natural: CGSize, available: CGSize) -> CGFloat {
        guard natural.width > 0, natural.height > 0 else { return 1 }
        return min(1, available.width / natural.width, available.height / natural.height)
    }
}
