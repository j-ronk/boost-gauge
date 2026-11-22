import AppKit
import SwiftUI

/// The Overview item's menu bar glyph: three tiny level bars for CPU, GPU and memory, each over a dim track.
struct OverviewGlyph: View {
    static let size = CGSize(width: 16, height: StackedLabel.height)
    static let barHeight: CGFloat = 13
    static let barWidth: CGFloat = 3.6
    static let barSpacing: CGFloat = 1.4
    /// A reading of 0% still shows a sliver, so a bar never reads as missing.
    static let minimumHeight: CGFloat = 2

    let heights: [CGFloat]
    var accessibilityText = "Overview"

    /// Rounded to the half point (one pixel at 2x), so a reading that moves less than a pixel reuses the cached image.
    /// No reading gives an empty track.
    static func heights(cpu: Double?, gpu: Double?, memory: Double?) -> [CGFloat] {
        [cpu, gpu, memory].map { percent in
            guard let percent, percent.isFinite else { return 0 }
            let h = max(minimumHeight, barHeight * min(100, max(0, percent)) / 100)
            return (h * 2).rounded() / 2
        }
    }

    // Each bar has 27 heights; recent combinations stay cached, as StackedLabel's values do.
    @MainActor private static let cache = LabelImageCache<[CGFloat]>(limit: 256)

    @MainActor var image: NSImage {
        Self.cache.image(for: heights) {
            MenuBarImage.render(Bars(heights: heights), size: Self.size)
        }
    }

    var body: some View {
        Image(nsImage: image)
            .renderingMode(.template)
            .accessibilityLabel(accessibilityText)
    }

    private struct Bars: View {
        let heights: [CGFloat]

        var body: some View {
            HStack(alignment: .bottom, spacing: OverviewGlyph.barSpacing) {
                ForEach(heights.indices, id: \.self) { i in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.2).opacity(0.28)
                        RoundedRectangle(cornerRadius: 1.2).frame(height: heights[i])
                    }
                    .frame(width: OverviewGlyph.barWidth, height: OverviewGlyph.barHeight)
                }
            }
            .foregroundStyle(.black)
        }
    }
}

/// Re-renders when the model's bar heights change, and only then.
struct OverviewLabel: View {
    let model: OverviewModel

    var body: some View {
        let r = model.reading
        OverviewGlyph(heights: model.glyph, accessibilityText:
            "Overview, CPU \(OverviewText.percent(r.cpu)), GPU \(OverviewText.percent(r.gpu)), Memory \(OverviewText.percent(r.memory?.usedPercent))")
    }
}
