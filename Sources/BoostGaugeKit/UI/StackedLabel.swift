import AppKit
import SwiftUI

/// Stats-style two-line menu bar label: a tiny caption over the value ("CPU" over "21%"),
/// or two values (Network up over down). Width is fixed by `widest` so the menu bar never jitters.
public struct StackedLabel: View {
    public static let height: CGFloat = 22

    private enum Lines: Hashable {
        case caption(String, value: String)
        case pair(top: String, bottom: String)
    }

    /// Same key `AppSettings.captionAlignment` writes. Read straight from defaults so every item honours it
    /// without passing settings in, and `@AppStorage` redraws labels the moment Settings changes it.
    static let captionAlignmentKey = "label.captionAlignment"

    /// Same key `AppSettings.largeValues` writes: a smaller caption over a bigger value, as Stats draws it.
    static let largeValuesKey = "label.largeValues"

    private let lines: Lines
    private let widest: String
    @AppStorage(StackedLabel.captionAlignmentKey) private var alignment: CaptionAlignment = .center
    @AppStorage(StackedLabel.largeValuesKey) private var largeValues = false

    public init(caption: String, value: String, widest: String) {
        lines = .caption(caption, value: value)
        self.widest = widest
    }

    public init(top: String, bottom: String, widest: String) {
        lines = .pair(top: top, bottom: bottom)
        self.widest = widest
    }

    @MainActor public var image: NSImage {
        image(alignment: Self.alignment(in: .standard), large: Self.largeValues(in: .standard))
    }

    private struct CacheKey: Hashable {
        let lines: Lines
        let width: CGFloat
        let alignment: CaptionAlignment
        let large: Bool
    }

    // Roomy, so a busy label (CPU, Network) can't push a quiet one's current image out; each is a few KB.
    @MainActor private static let cache = LabelImageCache<CacheKey>(limit: 256)

    @MainActor func image(alignment: CaptionAlignment, large: Bool = false) -> NSImage {
        // The pair label has no caption, so neither setting applies to it, and changing one mustn't hand it a new image.
        let isPair = if case .pair = lines { true } else { false }
        let style = Style(large: large && !isPair)
        let width = width(style)
        let key = CacheKey(lines: lines, width: width, alignment: isPair ? .center : alignment, large: style.large)
        return Self.cache.image(for: key) {
            MenuBarImage.render(content(alignment, style), size: CGSize(width: width, height: Self.height))
        }
    }

    /// Fixed by `widest`, never by the current value, so the menu bar never jitters.
    func width(large: Bool) -> CGFloat {
        let isPair = if case .pair = lines { true } else { false }
        return width(Style(large: large && !isPair))
    }

    private func width(_ style: Style) -> CGFloat {
        switch lines {
        case let .caption(caption, _):
            Self.width(max(style.measure(caption, style.captionNSFont), style.measure(widest, style.valueNSFont)))
        case .pair:
            Self.width(Style.measure(widest, Style.pairNSFont))
        }
    }

    static func alignment(in defaults: UserDefaults) -> CaptionAlignment {
        defaults.string(forKey: captionAlignmentKey).flatMap(CaptionAlignment.init) ?? .center
    }

    static func largeValues(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: largeValuesKey)
    }

    public var body: some View {
        Image(nsImage: image(alignment: alignment, large: largeValues))
            .renderingMode(.template)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private func content(_ alignment: CaptionAlignment, _ style: Style) -> some View {
        switch lines {
        case let .caption(caption, value):
            let horizontal: HorizontalAlignment = alignment == .leading ? .leading : .center
            VStack(alignment: horizontal, spacing: style.lineSpacing) {
                Text(caption)
                    .font(style.captionFont)
                    .opacity(style.captionOpacity)
                Text(value)
                    .font(style.valueFont)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.black)
            // Keeps the point of air that `width(_:)` adds on the left.
            .padding(.leading, alignment == .leading ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontal, vertical: .center))
            .offset(y: style.verticalNudge)
        case let .pair(top, bottom):
            VStack(alignment: .leading, spacing: 0) {
                Text(top)
                Text(bottom)
            }
            .font(Style.pairFont)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var accessibilityText: String {
        switch lines {
        case let .caption(caption, value): "\(caption) \(value)"
        case let .pair(top, bottom): "\(top), \(bottom)"
        }
    }

    // One point of air each side so neighbouring items don't touch.
    private static func width(_ text: CGFloat) -> CGFloat { (text + 2).rounded(.up) }

    /// Font sizes for the two looks. Each SwiftUI font has an AppKit twin, because the width must be known before rendering.
    private struct Style {
        let large: Bool

        var captionSize: CGFloat { large ? 7 : 8 }
        var valueSize: CGFloat { large ? 12 : 10 }
        var valueWeight: Font.Weight { large ? .bold : .semibold }
        var captionOpacity: Double { large ? 0.8 : 0.7 }
        // The big value's line box has more air than its glyphs need; overlapping it keeps both lines inside 22 pt.
        var lineSpacing: CGFloat { large ? -2.5 : 0 }
        var verticalNudge: CGFloat { 0 }

        var captionFont: Font { .system(size: captionSize, weight: .medium) }
        var valueFont: Font { .system(size: valueSize, weight: valueWeight).monospacedDigit() }
        var captionNSFont: NSFont { .systemFont(ofSize: captionSize, weight: .medium) }
        var valueNSFont: NSFont { .monospacedDigitSystemFont(ofSize: valueSize, weight: large ? .bold : .semibold) }

        static let pairFont = Font.system(size: 9, weight: .semibold).monospacedDigit()
        static let pairNSFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)

        func measure(_ s: String, _ font: NSFont) -> CGFloat { Self.measure(s, font) }

        static func measure(_ s: String, _ font: NSFont) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: font]).width
        }
    }
}
