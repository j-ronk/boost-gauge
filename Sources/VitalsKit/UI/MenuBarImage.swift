import AppKit
import SwiftUI

public enum MenuBarImage {
    /// Test seam: how many images have been drawn, so tests can prove unchanged labels don't redraw.
    @MainActor static private(set) var renderCount = 0

    /// Menu bar labels can only show one line of text, so anything richer goes up as a template image.
    /// Template images carry alpha only, and the menu bar tints them for light, dark and highlighted states.
    @MainActor public static func render(_ view: some View, size: CGSize) -> NSImage {
        renderCount += 1
        let renderer = ImageRenderer(content: view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        let image = renderer.cgImage.map { NSImage(cgImage: $0, size: size) } ?? NSImage(size: size)
        image.isTemplate = true
        return image
    }
}
