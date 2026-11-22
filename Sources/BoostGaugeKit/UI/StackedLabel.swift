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

    private let lines: Lines
    private let width: CGFloat
    @AppStorage(StackedLabel.captionAlignmentKey) private var alignment: CaptionAlignment = .center

    public init(caption: String, value: String, widest: String) {
        lines = .caption(caption, value: value)
        width = Self.width(max(Metrics.captionWidth(caption), Metrics.valueWidth(widest)))
    }

    public init(top: String, bottom: String, widest: String) {
        lines = .pair(top: top, bottom: bottom)
        width = Self.width(Metrics.pairWidth(widest))
    }

    @MainActor public var image: NSImage { image(alignment: Self.alignment(in: .standard)) }

    private struct CacheKey: Hashable {
        let lines: Lines
        let width: CGFloat
        let alignment: CaptionAlignment
    }

    // Roomy, so a busy label (CPU, Network) can't push a quiet one's current image out; each is a few KB.
    @MainActor private static let cache = LabelImageCache<CacheKey>(limit: 256)

    @MainActor func image(alignment: CaptionAlignment) -> NSImage {
        // The pair label ignores alignment, so an alignment change mustn't hand it a new image.
        let keyAlignment: CaptionAlignment = if case .pair = lines { .center } else { alignment }
        return Self.cache.image(for: CacheKey(lines: lines, width: width, alignment: keyAlignment)) {
            MenuBarImage.render(content(alignment), size: CGSize(width: width, height: Self.height))
        }
    }

    static func alignment(in defaults: UserDefaults) -> CaptionAlignment {
        defaults.string(forKey: captionAlignmentKey).flatMap(CaptionAlignment.init) ?? .center
    }

    public var body: some View {
        Image(nsImage: image(alignment: alignment))
            .renderingMode(.template)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private func content(_ alignment: CaptionAlignment) -> some View {
        switch (lines, alignment) {
        case let (.caption(caption, value), .center):
            VStack(spacing: 0) {
                Text(caption)
                    .font(Metrics.captionFont)
                    .opacity(0.7)
                Text(value)
                    .font(Metrics.valueFont)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.black)
        case let (.caption(caption, value), .leading):
            VStack(alignment: .leading, spacing: 0) {
                Text(caption)
                    .font(Metrics.captionFont)
                    .opacity(0.7)
                Text(value)
                    .font(Metrics.valueFont)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.black)
            // Keeps the point of air that `width(_:)` adds on the left.
            .padding(.leading, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
        case let (.pair(top, bottom), _):
            VStack(alignment: .leading, spacing: 0) {
                Text(top)
                Text(bottom)
            }
            .font(Metrics.pairFont)
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

    private enum Metrics {
        static let captionFont = Font.system(size: 8, weight: .medium)
        static let valueFont = Font.system(size: 10, weight: .semibold).monospacedDigit()
        static let pairFont = Font.system(size: 9, weight: .semibold).monospacedDigit()

        // Measured with the AppKit twins of the SwiftUI fonts above, because the width must be known before rendering.
        static func captionWidth(_ s: String) -> CGFloat { measure(s, .systemFont(ofSize: 8, weight: .medium)) }
        static func valueWidth(_ s: String) -> CGFloat { measure(s, .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)) }
        static func pairWidth(_ s: String) -> CGFloat { measure(s, .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)) }

        private static func measure(_ s: String, _ font: NSFont) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: font]).width
        }
    }
}
