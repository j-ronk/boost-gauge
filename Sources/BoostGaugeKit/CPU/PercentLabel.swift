import SwiftUI

/// A stacked "CAPTION / NN%" label that re-renders when the observable value it reads changes.
struct PercentLabel: View {
    let caption: String
    let value: () -> String

    var body: some View {
        StackedLabel(caption: caption, value: value(), widest: "100%")
    }
}

/// An app or process row: icon, name, value.
struct IconRow: View {
    let icon: NSImage
    let name: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            Text(name).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

extension FooterButton {
    static let activityMonitor = FooterButton.app("Activity Monitor…", bundleID: "com.apple.ActivityMonitor")
}
