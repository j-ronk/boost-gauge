import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable public final class SettingsModel {
    struct RefreshChoice: Hashable {
        let seconds: Int
        var title: String { "\(seconds) s" }
    }

    static let refreshChoices = AppSettings.allowedRefreshSeconds.map(RefreshChoice.init)

    @ObservationIgnored private let ctx: AppContext
    @ObservationIgnored private let loginItem: LoginItemControl
    // SMAppService isn't observable, so the toggle mirrors it and re-reads whenever Settings appears.
    private var loginItemOn: Bool

    public convenience init(_ ctx: AppContext) { self.init(ctx, loginItem: .system) }

    init(_ ctx: AppContext, loginItem: LoginItemControl) {
        self.ctx = ctx
        self.loginItem = loginItem
        loginItemOn = loginItem.isEnabled()
    }

    private var settings: AppSettings { ctx.settings }

    func shown(_ id: ItemID) -> Binding<Bool> {
        Binding(get: { self.settings.isShown(id) }, set: { self.settings.setShown(id, $0) })
    }

    var order: [ItemID] { settings.itemOrder }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = settings.itemOrder
        ItemOrder.move(&order, fromOffsets: source, toOffset: destination)
        settings.itemOrder = order
    }

    /// Live reorder while dragging: `dragged` takes `target`'s place, saving only when something moved.
    func drop(_ dragged: ItemID, onto target: ItemID) {
        let edge = ItemOrder.liveEdge(dragging: dragged, over: target, in: order)
        let moved = ItemOrder.dropping(dragged, on: target, edge: edge, in: order)
        if moved != order { settings.itemOrder = moved }
    }

    func canMove(_ id: ItemID, by step: Int) -> Bool {
        guard let index = order.firstIndex(of: id) else { return false }
        return order.indices.contains(index + step)
    }

    /// The context menu's Move Up and Move Down, for when a drag is awkward.
    func move(_ id: ItemID, by step: Int) {
        guard canMove(id, by: step), let index = order.firstIndex(of: id) else { return }
        move(fromOffsets: IndexSet(integer: index), toOffset: step > 0 ? index + step + 1 : index + step)
    }

    var showPercentage: Binding<Bool> {
        Binding(get: { self.settings.showBatteryPercentage }, set: { self.settings.showBatteryPercentage = $0 })
    }

    var refreshSeconds: Binding<Int> {
        Binding(get: { self.settings.refreshSeconds }, set: { self.settings.refreshSeconds = $0 })
    }

    var temperatureUnit: Binding<TemperatureUnit> {
        Binding(get: { self.settings.temperatureUnit }, set: { self.settings.temperatureUnit = $0 })
    }

    var networkUnit: Binding<NetworkUnit> {
        Binding(get: { self.settings.networkUnit }, set: { self.settings.networkUnit = $0 })
    }

    var captionAlignment: Binding<CaptionAlignment> {
        Binding(get: { self.settings.captionAlignment }, set: { self.settings.captionAlignment = $0 })
    }

    var launchAtLogin: Binding<Bool> {
        Binding(get: { self.loginItemOn }, set: {
            self.loginItem.setEnabled($0)
            self.refreshLoginItem()
        })
    }

    func refreshLoginItem() { loginItemOn = loginItem.isEnabled() }

    /// Nil hides the Energy Mode section.
    var energyModeStatus: String? { ctx.energyMode.map { Self.statusText($0.helperStatus) } }

    func openLoginItems() { ctx.energyMode?.openLoginItems() }

    static func title(_ id: ItemID) -> String {
        switch id {
        case .battery: "Battery"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .temps: "Temperatures"
        case .network: "Network"
        case .disk: "Disk"
        case .power: "Power"
        }
    }

    static func title(_ unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    static func title(_ unit: NetworkUnit) -> String {
        switch unit {
        case .bytes: "Bytes"
        case .bits: "Bits"
        }
    }

    static func title(_ alignment: CaptionAlignment) -> String {
        switch alignment {
        case .center: "Centered"
        case .leading: "Left"
        }
    }

    static func statusText(_ status: HelperStatus) -> String {
        switch status {
        case .enabled: "On"
        case .requiresApproval: "Needs Approval"
        case .notRegistered, .unavailable: "Off"
        }
    }
}

struct SettingsView: View {
    let model: SettingsModel
    @State private var dragging: ItemID?

    var body: some View {
        Form {
            Section("Menu Bar") {
                ForEach(model.order, id: \.self) { id in
                    Toggle(isOn: model.shown(id)) {
                        Label {
                            Text(SettingsModel.title(id))
                        } icon: {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    // A grouped Form ignores onMove on macOS, so rows drag and drop themselves.
                    .onDrag {
                        dragging = id
                        let provider = NSItemProvider()
                        provider.registerDataRepresentation(for: .boostGaugeItem) { done in
                            done(Data(id.rawValue.utf8), nil)
                            return nil
                        }
                        return provider
                    }
                    .onDrop(of: [.boostGaugeItem], delegate: RowDropDelegate(target: id, model: model, dragging: $dragging))
                    .contextMenu {
                        Button("Move Up") { model.move(id, by: -1) }.disabled(!model.canMove(id, by: -1))
                        Button("Move Down") { model.move(id, by: 1) }.disabled(!model.canMove(id, by: 1))
                    }
                }
                Toggle("Show Battery Percentage", isOn: model.showPercentage)
                    .disabled(!model.shown(.battery).wrappedValue)
                Picker("Refresh", selection: model.refreshSeconds) {
                    ForEach(SettingsModel.refreshChoices, id: \.self) { Text($0.title).tag($0.seconds) }
                }
            }
            Section("Display") {
                Picker("Temperature", selection: model.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { Text(SettingsModel.title($0)).tag($0) }
                }
                Picker("Network", selection: model.networkUnit) {
                    ForEach(NetworkUnit.allCases, id: \.self) { Text(SettingsModel.title($0)).tag($0) }
                }
                Picker("Label Alignment", selection: model.captionAlignment) {
                    ForEach(CaptionAlignment.allCases, id: \.self) { Text(SettingsModel.title($0)).tag($0) }
                }
            }
            Section("General") {
                Toggle("Launch at Login", isOn: model.launchAtLogin)
            }
            if let status = model.energyModeStatus {
                Section("Energy Mode") {
                    LabeledContent("Status", value: status)
                    Button("Open Login Items…") { model.openLoginItems() }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 420)
        .onAppear { model.refreshLoginItem() }
    }
}

/// Rows reorder as the drag passes over them, like System Settings; the drop itself only ends the drag.
private struct RowDropDelegate: DropDelegate {
    let target: ItemID
    let model: SettingsModel
    @Binding var dragging: ItemID?

    // `dragging` outlives a cancelled drag, so only our own row type may reorder.
    func validateDrop(info: DropInfo) -> Bool { dragging != nil && info.hasItemsConforming(to: [.boostGaugeItem]) }

    func dropEntered(info: DropInfo) {
        guard let dragged = dragging, dragged != target else { return }
        withAnimation(.snappy) { model.drop(dragged, onto: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private extension UTType {
    /// Private, so a row can't be dropped into another app as text and foreign drags can't reorder rows.
    static let boostGaugeItem = UTType(exportedAs: "\(Bundle.main.bundleIdentifier ?? "BoostGauge").item", conformingTo: .data)
}
