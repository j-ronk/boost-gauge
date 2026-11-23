import AppKit
import Testing
@testable import BoostGaugeKit

@MainActor
struct LargeValuesTests {
    @Test func offByDefaultAndPersists() {
        let suite = TestDefaults()
        #expect(AppSettings(defaults: suite.defaults).largeValues == false)
        #expect(StackedLabel.largeValues(in: suite.defaults) == false)
        AppSettings(defaults: suite.defaults).largeValues = true
        #expect(AppSettings(defaults: suite.defaults).largeValues)
        #expect(StackedLabel.largeValues(in: suite.defaults))
    }

    @Test(arguments: CaptionAlignment.allCases)
    func largeLabelFitsTheMenuBar(alignment: CaptionAlignment) throws {
        for (caption, value, widest) in [("CPU", "100%", "100%"), ("TEMP", "88°C", "100°C"), ("SSD", "1.2 GB/s", "999 MB/s"),
                                         ("POWER", "188W", "188W"), ("GPU", "—", "100%")] {
            let image = StackedLabel(caption: caption, value: value, widest: widest).image(alignment: alignment, large: true)
            #expect(image.size.height == StackedLabel.height)
            let ink = try Self.inkBounds(image)
            // Nothing clipped: a clear pixel row above and below, and a clear column each side.
            #expect(ink.minY >= 1 && ink.maxY <= 42, "\(caption) \(value) rows \(ink.minY)...\(ink.maxY)")
            #expect(ink.minX >= 1 && ink.maxX <= Int(image.size.width * 2) - 2, "\(caption) \(value) cols \(ink.minX)...\(ink.maxX)")
        }
    }

    @Test func valueTakesMoreOfTheHeightThanTheDefault() throws {
        // No caption, so the ink is the value's glyphs alone.
        let label = StackedLabel(caption: "", value: "88%", widest: "100%")
        let normal = try Self.inkBounds(label.image(alignment: .center, large: false))
        let large = try Self.inkBounds(label.image(alignment: .center, large: true))
        #expect(Double(large.maxY - large.minY) > Double(normal.maxY - normal.minY) * 1.15)
    }

    @Test(arguments: CaptionAlignment.allCases)
    func captionAndValueDontTouch(alignment: CaptionAlignment) throws {
        // A space keeps the other line's height, so each line lands where it does in the full label.
        let caption = try Self.inkBounds(StackedLabel(caption: "POWER", value: " ", widest: "188W").image(alignment: alignment, large: true))
        let value = try Self.inkBounds(StackedLabel(caption: " ", value: "188W", widest: "188W").image(alignment: alignment, large: true))
        #expect(caption.maxY < value.minY, "caption rows ...\(caption.maxY), value rows \(value.minY)...")
    }

    @Test func widthIsStableAsValuesChange() {
        for large in [false, true] {
            let widths = ["0%", "7%", "24%", "100%", "—"].map {
                StackedLabel(caption: "CPU", value: $0, widest: "100%").image(alignment: .center, large: large).size.width
            }
            #expect(Set(widths).count == 1)
            let temps = ["9°C", "62°C", "100°C"].map {
                StackedLabel(caption: "TEMP", value: $0, widest: "100°C").image(alignment: .leading, large: large).size.width
            }
            #expect(Set(temps).count == 1)
        }
        let label = StackedLabel(caption: "CPU", value: "24%", widest: "100%")
        #expect(label.width(large: true) == label.image(alignment: .center, large: true).size.width)
        #expect(label.width(large: true) > label.width(large: false))
    }

    @Test func toggleRedrawsCaptionLabelsButNotThePair() {
        let label = StackedLabel(caption: "CPU", value: "41%", widest: "100%")
        #expect(label.image(alignment: .center, large: true) !== label.image(alignment: .center, large: false))
        #expect(label.image(alignment: .center, large: true) === label.image(alignment: .center, large: true))
        let pair = StackedLabel(top: "↑ 5K", bottom: "↓ 7K", widest: "↓ 999M")
        #expect(pair.image(alignment: .center, large: true) === pair.image(alignment: .center, large: false))
        #expect(pair.width(large: true) == pair.width(large: false))
    }

    /// Pixel bounds of everything drawn, top-left origin, at the image's 2x scale.
    static func inkBounds(_ image: NSImage) throws -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: cg)
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        try #require(maxY >= 0, "nothing drawn")
        return (minX, maxX, minY, maxY)
    }
}
