import AppKit
import Testing
@testable import VitalsKit

@MainActor
struct StackedLabelAlignmentTests {
    @Test func readsTheSettingsKey() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        #expect(StackedLabel.alignment(in: suite.defaults) == .center)
        settings.captionAlignment = .leading
        #expect(StackedLabel.alignment(in: suite.defaults) == .leading)
    }

    @Test func leftAlignmentMovesTheCaption() throws {
        let label = StackedLabel(caption: "CPU", value: "7%", widest: "100%")
        let center = try #require(label.image(alignment: .center).tiffRepresentation)
        let left = try #require(label.image(alignment: .leading).tiffRepresentation)
        #expect(center != left)
        #expect(label.image(alignment: .leading).size == label.image(alignment: .center).size)
    }
}
