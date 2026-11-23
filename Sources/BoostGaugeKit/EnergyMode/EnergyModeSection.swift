import AppKit
import SwiftUI

/// "Energy Mode · <source>" and a picker for that source only.
struct EnergyModeSection: View {
    let controller: EnergyModeController

    var body: some View {
        PanelSection("Energy Mode", detail: controller.sourceTitle) {
            EnergyModePicker(selection: Binding(
                get: { controller.pickerSelection },
                set: { mode in
                    guard let mode else { return }
                    Task { await controller.select(mode) }
                }
            ))
            .disabled(controller.displayedMode == nil)
            // A refused pick leaves the binding unchanged; rebuilding drops any half-run thumb animation.
            .id(controller.refusals)
        }
        // Panel open is one of only two times pmset is read; the other is a power source change.
        .task { await controller.refresh() }
    }
}

struct EnergyModePicker: View {
    @Binding var selection: EnergyMode?

    var body: some View {
        CapsulePicker(title: "Energy Mode", selection: $selection, options: EnergyMode.pickerOrder.map(Self.option))
            .font(.callout)
    }

    static func option(_ mode: EnergyMode) -> CapsulePicker<EnergyMode>.Option {
        .init(value: mode, title: mode.title, symbol: mode.symbol, tint: thumbTint(mode))
    }

    /// Low Power is yellow, as the battery icon is in Low Power Mode; the other modes keep the neutral thumb.
    static func thumbTint(_ mode: EnergyMode) -> Color? {
        mode == .low ? Color(nsColor: .systemYellow) : nil
    }
}

extension EnergyMode {
    var symbol: String {
        switch self {
        case .low: "leaf.fill"
        case .automatic: "circle.lefthalf.filled"
        case .high: "bolt.fill"
        }
    }
}

/// Every state of the panel's two pickers, for `--render`.
public struct ControlSamples: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([EnergyMode.low, .automatic, .high], id: \.self) { mode in
                EnergyModePicker(selection: .constant(mode))
            }
            EnergyModePicker(selection: .constant(nil)).disabled(true)
            ChargeRangePicker(selection: .constant(.shared(.day)))
            ChargeRangePicker(selection: .constant(.tenDays))
        }
        .padding()
        .frame(width: 300)
    }
}
