import AppKit
import SwiftUI

/// The Overview item's menu bar glyph: one tiny level bar per chosen stat, each over a dim track.
/// Every edge sits on a whole point, so the 2x image scales down to 1x displays without blurring.
struct OverviewGlyph: View {
    static let barHeight: CGFloat = 14
    static let barWidth: CGFloat = 4
    static let barSpacing: CGFloat = 2
    static let inset: CGFloat = 1
    /// A reading of 0% still shows a sliver, so a bar never reads as missing.
    static let minimumHeight: CGFloat = 2

    let heights: [CGFloat]
    var accessibilityText = "Overview"

    /// Grows with the bar count; the height matches the other labels.
    static func size(bars: Int) -> CGSize {
        let n = CGFloat(max(1, bars))
        return CGSize(width: n * barWidth + (n - 1) * barSpacing + 2 * inset, height: StackedLabel.height)
    }

    /// Levels are 0…100 (percent, or °C for temperatures), rounded to whole points: crisp at 1x, and a reading that
    /// moves less than a point reuses the cached image. No reading gives an empty track.
    static func heights(_ levels: [Double?]) -> [CGFloat] {
        levels.map { level in
            guard let level, level.isFinite else { return 0 }
            return max(minimumHeight, (barHeight * min(100, max(0, level)) / 100).rounded())
        }
    }

    // Each bar has 13 heights; recent combinations stay cached, as StackedLabel's values do.
    @MainActor private static let cache = LabelImageCache<[CGFloat]>(limit: 256)

    @MainActor var image: NSImage {
        Self.cache.image(for: heights) {
            MenuBarImage.render(Bars(heights: heights), size: Self.size(bars: heights.count))
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
                        RoundedRectangle(cornerRadius: 1).opacity(0.28)
                        RoundedRectangle(cornerRadius: 1).frame(height: heights[i])
                    }
                    .frame(width: OverviewGlyph.barWidth, height: OverviewGlyph.barHeight)
                }
            }
            .foregroundStyle(.black)
        }
    }
}

/// The glyph for the given stats at the model's reading. The image is cached by bar heights, so a beat that moves
/// no bar by a whole point redraws nothing.
struct OverviewLabel: View {
    let model: OverviewModel
    let metrics: [OverviewMetric]

    var body: some View {
        OverviewGlyph(heights: Self.heights(metrics, model.reading), accessibilityText: Self.accessibilityText(metrics, model.reading))
    }

    static func heights(_ metrics: [OverviewMetric], _ r: OverviewReading) -> [CGFloat] {
        OverviewGlyph.heights(metrics.map { $0.glyphLevel(r) })
    }

    /// "Overview, CPU 29%, GPU 100%, Hottest 72°C": the chosen stats, left to right.
    static func accessibilityText(_ metrics: [OverviewMetric], _ r: OverviewReading) -> String {
        (["Overview"] + metrics.map { "\($0.title(in: .bars)) \(OverviewText.glyphValue($0, r))" }).joined(separator: ", ")
    }
}

/// The menu bar's glyph: follows Settings' choice of stats as it changes.
struct OverviewLiveLabel: View {
    let model: OverviewModel
    let settings: AppSettings

    var body: some View { OverviewLabel(model: model, metrics: settings.overviewGlyphMetrics) }
}
