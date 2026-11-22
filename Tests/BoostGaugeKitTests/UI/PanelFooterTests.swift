import AppKit
import SwiftUI
import Testing
@testable import BoostGaugeKit

@MainActor
struct PanelFooterTests {
    // The panel is 300 pt with 16 pt padding each side.
    private let contentWidth: CGFloat = 268

    private func naturalWidth(_ button: FooterButton?) -> CGFloat {
        NSHostingView(rootView: PanelFooter(button: button).fixedSize()).fittingSize.width
    }

    @Test func itemRowAndIconsFitWithRoomToSpare() {
        let titles = ["Battery Settings…", "Network Settings…", "Activity Monitor…", "Disk Utility…"]
        for title in titles {
            let width = naturalWidth(.app(title, bundleID: "com.example"))
            // At least a 40 pt gap between the item row's text and the icons.
            #expect(width <= contentWidth - 40, "\(title): \(width)")
        }
    }

    @Test func iconsStayTrailingWithoutItemButton() {
        #expect(naturalWidth(nil) < 80)
    }

    @Test func iconLabelsAndSymbols() {
        #expect(PanelFooter.settings.label == "Settings")
        #expect(PanelFooter.settings.symbol == "gearshape")
        #expect(PanelFooter.quit.label == "Quit Boost Gauge")
        #expect(PanelFooter.quit.symbol == "power")
    }
}
