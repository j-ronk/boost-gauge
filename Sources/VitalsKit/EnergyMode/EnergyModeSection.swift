import SwiftUI

/// "Energy Mode · <source>" and a segmented picker for that source only.
struct EnergyModeSection: View {
    let controller: EnergyModeController

    var body: some View {
        PanelSection("Energy Mode", detail: controller.sourceTitle) {
            Picker("Energy Mode", selection: Binding(
                get: { controller.pickerSelection },
                set: { mode in
                    guard let mode else { return }
                    Task { await controller.select(mode) }
                }
            )) {
                ForEach(EnergyMode.pickerOrder, id: \.self) { mode in
                    Text(mode.title).tag(Optional(mode))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(controller.displayedMode == nil)
            // A refused pick leaves the binding unchanged, so the native control would keep showing the clicked segment.
            .id(controller.refusals)
        }
        // Panel open is one of only two times pmset is read; the other is a power source change.
        .task { await controller.refresh() }
    }
}
