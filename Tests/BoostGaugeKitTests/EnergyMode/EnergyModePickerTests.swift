import SwiftUI
import Testing
@testable import BoostGaugeKit

@MainActor
struct EnergyModePickerTests {
    @Test func segmentsFollowSystemSettingsOrderWithIcons() {
        let options = EnergyMode.pickerOrder.map(EnergyModePicker.option)
        #expect(options.map(\.value) == [.low, .automatic, .high])
        #expect(options.map(\.title) == ["Low Power", "Automatic", "High Power"])
        #expect(options.map(\.symbol) == ["leaf.fill", "circle.lefthalf.filled", "bolt.fill"])
    }

    /// Only Low Power tints the thumb, matching the battery icon; High Power keeps the neutral thumb (Jay, 22 Nov).
    @Test func onlyLowPowerHasAYellowThumb() {
        #expect(EnergyModePicker.thumbTint(.low) == Color(nsColor: .systemYellow))
        #expect(EnergyModePicker.thumbTint(.automatic) == nil)
        #expect(EnergyModePicker.thumbTint(.high) == nil)
    }

    @Test func selectedSegmentIsTheBoundValue() {
        let picker = CapsulePicker(title: "Energy Mode", selection: .constant(EnergyMode.high),
                                   options: EnergyMode.pickerOrder.map(EnergyModePicker.option))
        #expect(picker.options.filter(picker.isSelected).map(\.value) == [.high])
        let unread = CapsulePicker(title: "Energy Mode", selection: .constant(EnergyMode?.none),
                                   options: EnergyMode.pickerOrder.map(EnergyModePicker.option))
        #expect(unread.options.filter(unread.isSelected).isEmpty)
    }
}
