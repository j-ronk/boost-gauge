import AppKit
import Testing
@testable import VitalsKit

@MainActor
struct StackedLabelTests {
    @Test func widthIsFixedByWidest() {
        let low = StackedLabel(caption: "CPU", value: "7%", widest: "100%").image
        let high = StackedLabel(caption: "CPU", value: "100%", widest: "100%").image
        #expect(low.size.width == high.size.width)
        #expect(low.size.width > 0)
        #expect(low.size.height == 22)
        #expect(high.size.height == StackedLabel.height)
        #expect(low.isTemplate)
        #expect(high.isTemplate)
    }

    @Test func twoValueLabelIsFixedWidthTemplate() {
        let a = StackedLabel(top: "↑ 0K", bottom: "↓ 0K", widest: "↓ 999M").image
        let b = StackedLabel(top: "↑ 12K", bottom: "↓ 1.2M", widest: "↓ 999M").image
        #expect(a.size.width == b.size.width)
        #expect(a.size.height == 22)
        #expect(a.isTemplate)
    }

    @Test func imageHasPixelsAtScaleTwo() throws {
        let image = StackedLabel(caption: "CPU", value: "21%", widest: "100%").image
        let rep = try #require(image.representations.first)
        #expect(rep.pixelsHigh == 44)
    }
}

/// The menu bar re-reads a label whenever SwiftUI says it may have changed. A fresh NSImage on every read made
/// the MenuBarExtra host schedule another update, forever (~100% CPU idle). Same content must be the same image.
@MainActor
struct StackedLabelCacheTests {
    @Test func sameContentIsTheSameImageWithoutRerendering() {
        let before = MenuBarImage.renderCount
        let a = StackedLabel(caption: "CPU", value: "37%", widest: "100%").image(alignment: .center)
        let b = StackedLabel(caption: "CPU", value: "37%", widest: "100%").image(alignment: .center)
        #expect(a === b)
        #expect(MenuBarImage.renderCount - before <= 1)
    }

    @Test func changedContentIsANewImage() {
        let label = StackedLabel(caption: "CPU", value: "38%", widest: "100%")
        let center = label.image(alignment: .center)
        #expect(StackedLabel(caption: "CPU", value: "39%", widest: "100%").image(alignment: .center) !== center)
        #expect(label.image(alignment: .leading) !== center)
        #expect(StackedLabel(caption: "GPU", value: "38%", widest: "100%").image(alignment: .center) !== center)
        #expect(StackedLabel(caption: "CPU", value: "38%", widest: "100.0%").image(alignment: .center) !== center)
        #expect(StackedLabel(top: "CPU", bottom: "38%", widest: "100%").image(alignment: .center) !== center)
    }

    @Test func pairLabelIgnoresAlignment() {
        let pair = StackedLabel(top: "↑ 3K", bottom: "↓ 9K", widest: "↓ 999M")
        #expect(pair.image(alignment: .leading) === pair.image(alignment: .center))
        #expect(StackedLabel(caption: "SSD", value: "41G", widest: "999G").image
            === StackedLabel(caption: "SSD", value: "41G", widest: "999G").image)
    }

    @Test func cacheEvictsOldestPastItsLimit() {
        let cache = LabelImageCache<Int>(limit: 2)
        let one = cache.image(for: 1) { NSImage(size: .zero) }
        _ = cache.image(for: 2) { NSImage(size: .zero) }
        #expect(cache.image(for: 1) { NSImage(size: .zero) } === one)
        _ = cache.image(for: 3) { NSImage(size: .zero) }
        #expect(cache.count == 2)
        // 2 was least recently used, so it went; 1 survived because it was read again.
        #expect(cache.image(for: 1) { NSImage(size: .zero) } === one)
    }
}
