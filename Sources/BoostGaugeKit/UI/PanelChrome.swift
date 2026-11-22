import AppKit
import SwiftUI

/// The shared 300 pt panel: content sections, then the footer.
/// Dividers between top-level children are automatic, so a section hidden by an `if` never leaves a double rule.
public struct PanelChrome<Content: View>: View {
    private let footer: FooterButton?
    private let content: Content

    public init(footer: FooterButton?, @ViewBuilder content: () -> Content) {
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group(subviews: content) { sections in
                ForEach(sections.indices, id: \.self) { i in
                    if i > 0 { Divider() }
                    sections[i]
                }
            }
            Divider()
            PanelFooter(button: footer)
        }
        .padding()
        .frame(width: 300)
    }
}

public struct PanelHeader: View {
    private let title: String
    private let subtitle: String?
    private let bigValue: String?

    public init(title: String, subtitle: String?, bigValue: String?) {
        self.title = title
        self.subtitle = subtitle
        self.bigValue = bigValue
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if let bigValue {
                Text(bigValue)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
        }
    }
}

public struct PanelSection<Content: View>: View {
    private let title: String
    private let detail: String?
    private let content: Content

    public init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content
        }
    }

    private var heading: String {
        detail.map { "\(title) · \($0)" } ?? title
    }
}

public struct StatRow: View {
    private let label: String
    private let value: String

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// The item-specific footer button: opens a System Settings pane or a related app.
public struct FooterButton {
    enum Target: Equatable {
        case url(URL)
        case app(bundleID: String)
    }

    public let title: String
    let target: Target

    public static func url(_ title: String, _ url: URL) -> Self {
        Self(title: title, target: .url(url))
    }

    public static func app(_ title: String, bundleID: String) -> Self {
        Self(title: title, target: .app(bundleID: bundleID))
    }

    @MainActor func perform() {
        switch target {
        case let .url(url):
            NSWorkspace.shared.open(url)
        case let .app(bundleID):
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// [item row ················ ⚙ ⏻]: the item button as a full-width menu row, like the last row of
/// macOS's own Battery and Wi-Fi menus, with Settings and Quit as small trailing icons.
struct PanelFooter: View {
    struct Icon {
        let label: String
        let symbol: String
    }

    static let settings = Icon(label: "Settings", symbol: "gearshape")
    static let quit = Icon(label: "Quit Boost Gauge", symbol: "power")

    let button: FooterButton?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 2) {
            if let button {
                Button { button.perform() } label: {
                    Text(button.title)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MenuRowStyle())
            } else {
                Spacer(minLength: 0)
            }
            iconButton(Self.settings) {
                // An accessory app's Settings window opens behind the frontmost app unless we activate first.
                NSApp.activate()
                openSettings()
            }
            iconButton(Self.quit) { NSApp.terminate(nil) }
        }
        // The row highlight reaches past the content inset, as menu highlights do; the power glyph's
        // right edge lines up with the content above.
        .padding(.leading, -MenuRowStyle.inset)
        .padding(.trailing, -FooterIconStyle.glyphInset)
    }

    private func iconButton(_ icon: Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(icon.label, systemImage: icon.symbol).labelStyle(.iconOnly)
        }
        .buttonStyle(FooterIconStyle())
        .help(icon.label)
    }
}

/// Plain text with a rounded hover highlight, matching a Control Center style menu row.
private struct MenuRowStyle: ButtonStyle {
    static let inset: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(pressed: configuration.isPressed, shape: RoundedRectangle(cornerRadius: 6)) {
            configuration.label
                .padding(.horizontal, Self.inset)
                .padding(.vertical, 4)
        }
    }
}

private struct FooterIconStyle: ButtonStyle {
    static let size: CGFloat = 26
    /// Gap between the hit circle's edge and a body-size glyph.
    static let glyphInset: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(pressed: configuration.isPressed, shape: Circle()) {
            configuration.label
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: Self.size, height: Self.size)
        }
    }
}

private struct HoverHighlight<S: Shape, Content: View>: View {
    let pressed: Bool
    let shape: S
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        content
            .contentShape(shape)
            .background(shape.fill(.primary.opacity(pressed ? 0.16 : hovering ? 0.1 : 0)))
            .onHover { hovering = $0 }
    }
}
