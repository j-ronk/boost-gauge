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

    func sectionShown(_ section: PanelSectionID) -> Binding<Bool> {
        Binding(get: { self.settings.isSectionShown(section) }, set: { self.settings.setSectionShown(section, $0) })
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

    var overviewStyle: Binding<OverviewStyle> {
        Binding(get: { self.settings.overviewStyle }, set: { self.settings.overviewStyle = $0 })
    }

    var overviewHidesOthers: Binding<Bool> {
        Binding(get: { self.settings.overviewHidesOthers }, set: { self.settings.overviewHidesOthers = $0 })
    }

    var overviewReplacesOthers: Bool { settings.overviewReplacesOthers }

    /// The item's switch does nothing while Overview stands in for it.
    func isReplacedByOverview(_ id: ItemID) -> Bool { id != .overview && settings.overviewReplacesOthers }

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
        case .overview: "Overview"
        }
    }

    static func title(_ style: OverviewStyle) -> String {
        switch style {
        case .bars: "Bars"
        case .list: "List"
        case .tiles: "Tiles"
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

enum SettingsPane: Hashable {
    case general, menuBar
    case item(ItemID)

    /// Overview leads, as it does in the menu bar. Power sits beside Battery, whose panel it shares sections with;
    /// the rest follow menu bar declaration order.
    static let items: [ItemID] = [.overview, .battery, .power, .cpu, .gpu, .memory, .temps, .network, .disk]

    @MainActor var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu Bar"
        case let .item(id): SettingsModel.title(id)
        }
    }

    var icon: SettingsIcon {
        switch self {
        case .general: SettingsIcon(symbol: "gearshape.fill", color: .gray)
        case .menuBar: SettingsIcon(symbol: "menubar.rectangle", color: .gray)
        case .item(.battery): SettingsIcon(symbol: "battery.75percent", color: .green)
        case .item(.power): SettingsIcon(symbol: "bolt.fill", color: .yellow)
        case .item(.cpu): SettingsIcon(symbol: "cpu", color: .blue)
        case .item(.gpu): SettingsIcon(symbol: "display", color: .indigo)
        case .item(.memory): SettingsIcon(symbol: "memorychip", color: .teal)
        case .item(.temps): SettingsIcon(symbol: "thermometer.medium", color: .orange)
        case .item(.network): SettingsIcon(symbol: "arrow.up.arrow.down", color: .blue)
        case .item(.disk): SettingsIcon(symbol: "internaldrive", color: .gray)
        case .item(.overview): SettingsIcon(symbol: "chart.bar.fill", color: .purple)
        }
    }
}

/// A white glyph on a coloured rounded square, as in System Settings' sidebar.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color.gradient))
            .accessibilityHidden(true)
    }
}

struct SettingsView: View {
    let model: SettingsModel
    @State private var pane: SettingsPane?

    init(model: SettingsModel, pane: SettingsPane = .general) {
        self.model = model
        _pane = State(initialValue: pane)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section {
                    row(.general)
                    row(.menuBar)
                }
                Section("Items") {
                    ForEach(SettingsPane.items, id: \.self) { row(.item($0)) }
                }
            }
            // The column width alone was ignored in offscreen renders; a minimum on the list holds it.
            .frame(minWidth: 200)
            .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            let pane = pane ?? .general
            detail(pane)
                .formStyle(.grouped)
                .navigationTitle(pane.title)
        }
        .frame(width: 700, height: 560)
        .onAppear { model.refreshLoginItem() }
    }

    private func row(_ pane: SettingsPane) -> some View {
        Label { Text(pane.title) } icon: { pane.icon }
            .tag(pane)
    }

    @ViewBuilder private func detail(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPage(model: model)
        case .menuBar: MenuBarPage(model: model)
        case .item(.overview): OverviewPage(model: model)
        case let .item(id): ItemPage(model: model, id: id)
        }
    }
}

private struct GeneralPage: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: model.launchAtLogin)
                Picker("Refresh", selection: model.refreshSeconds) {
                    ForEach(SettingsModel.refreshChoices, id: \.self) { Text($0.title).tag($0.seconds) }
                }
            }
            Section("Units") {
                Picker("Temperature", selection: model.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { Text(SettingsModel.title($0)).tag($0) }
                }
                Picker("Network", selection: model.networkUnit) {
                    ForEach(NetworkUnit.allCases, id: \.self) { Text(SettingsModel.title($0)).tag($0) }
                }
            }
            if let status = model.energyModeStatus {
                Section("Energy Mode") {
                    LabeledContent("Status", value: status)
                    Button("Open Login Items…") { model.openLoginItems() }
                }
            }
        }
    }
}

private struct MenuBarPage: View {
    let model: SettingsModel
    @State private var dragging: ItemID?

    var body: some View {
        Form {
            Section {
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
                    .disabled(model.isReplacedByOverview(id))
                    .contextMenu {
                        Button("Move Up") { model.move(id, by: -1) }.disabled(!model.canMove(id, by: -1))
                        Button("Move Down") { model.move(id, by: 1) }.disabled(!model.canMove(id, by: 1))
                    }
                }
            } header: {
                Text("Items")
            } footer: {
                if model.overviewReplacesOthers {
                    Text("Hidden while Overview replaces them.").foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Show Battery Percentage", isOn: model.showPercentage)
                    .disabled(!model.shown(.battery).wrappedValue)
                Picker("Label Alignment", selection: model.captionAlignment) {
                    ForEach(CaptionAlignment.allCases, id: \.self) { Text(SettingsModel.title($0)).tag($0) }
                }
            }
        }
    }
}

private struct OverviewPage: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Show in Menu Bar", isOn: model.shown(.overview))
                Toggle("Hide Other Items", isOn: model.overviewHidesOthers)
                    .disabled(!model.shown(.overview).wrappedValue)
            }
            Section("Panel") {
                Picker("Style", selection: model.overviewStyle) {
                    ForEach(OverviewStyle.allCases, id: \.self) { Text(SettingsModel.title($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

private struct ItemPage: View {
    let model: SettingsModel
    let id: ItemID

    var body: some View {
        Form {
            Section {
                Toggle("Show in Menu Bar", isOn: model.shown(id))
            }
            Section("Panel") {
                ForEach(PanelSectionID.sections(of: id), id: \.self) { section in
                    Toggle(section.title, isOn: model.sectionShown(section))
                }
            }
        }
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
