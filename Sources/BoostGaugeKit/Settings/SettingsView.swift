import SwiftUI

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

    /// The selected style's metrics in the shared order, shown or not.
    var overviewMetrics: [OverviewMetric] {
        let allowed = Set(settings.overviewStyle.metrics)
        return settings.overviewOrder.filter(allowed.contains)
    }

    func metricShown(_ metric: OverviewMetric) -> Binding<Bool> {
        Binding(get: { self.settings.isOverviewMetricShown(metric) }, set: { self.settings.setOverviewMetricShown(metric, $0) })
    }

    /// A drag in the Contents list, whose offsets count only the style's metrics. The others keep their places.
    func moveMetrics(fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = overviewMetrics
        ItemOrder.move(&list, fromOffsets: source, toOffset: destination)
        settings.overviewOrder = ItemOrder.reordering(settings.overviewOrder, shownAs: list)
    }

    /// The neighbour in the list as shown, which skips the metrics the style doesn't use.
    private func neighbour(of metric: OverviewMetric, by step: Int) -> OverviewMetric? {
        let list = overviewMetrics
        guard let index = list.firstIndex(of: metric), list.indices.contains(index + step) else { return nil }
        return list[index + step]
    }

    func canMoveMetric(_ metric: OverviewMetric, by step: Int) -> Bool { neighbour(of: metric, by: step) != nil }

    func moveMetric(_ metric: OverviewMetric, by step: Int) {
        guard let target = neighbour(of: metric, by: step) else { return }
        settings.moveOverviewMetric(metric, onto: target)
    }

    /// The page Settings last showed.
    var lastPane: SettingsPane? {
        get { SettingsPane(storageKey: settings.settingsPane) }
        set { settings.settingsPane = newValue?.storageKey }
    }

    // MARK: Overview glyph

    /// Every stat the glyph can show, in its order, chosen or not.
    var glyphMetrics: [OverviewMetric] { settings.overviewGlyphOrder }

    func glyphShown(_ metric: OverviewMetric) -> Binding<Bool> {
        Binding(get: { self.settings.isGlyphMetricShown(metric) }, set: { self.settings.setGlyphMetricShown(metric, $0) })
    }

    func canToggleGlyph(_ metric: OverviewMetric) -> Bool { settings.canToggleGlyphMetric(metric) }

    func moveGlyphMetrics(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = settings.overviewGlyphOrder
        ItemOrder.move(&order, fromOffsets: source, toOffset: destination)
        settings.overviewGlyphOrder = order
    }

    func canMoveGlyphMetric(_ metric: OverviewMetric, by step: Int) -> Bool {
        guard let index = glyphMetrics.firstIndex(of: metric) else { return false }
        return glyphMetrics.indices.contains(index + step)
    }

    func moveGlyphMetric(_ metric: OverviewMetric, by step: Int) {
        guard canMoveGlyphMetric(metric, by: step), let index = glyphMetrics.firstIndex(of: metric) else { return }
        settings.moveOverviewGlyphMetric(metric, onto: glyphMetrics[index + step])
    }

    // MARK: Previews

    func item(_ id: ItemID) -> (any BoostGaugeItem)? { ctx.scheduler.item(id) }

    /// Left to right, what the menu bar holds now.
    var menuBarItems: [ItemID] { settings.itemOrder.filter { settings.isShown($0) && ctx.scheduler.item($0) != nil } }

    func previewOpened(_ id: ItemID) {
        if let item = item(id) { ctx.panels.opened(item) }
    }

    func previewClosed(_ id: ItemID) {
        if let item = item(id) { ctx.panels.closed(item) }
    }

    /// Ticks the previewed item at the refresh rate while nothing else does, for as long as its page is on screen.
    func samplePreview(_ id: ItemID) async {
        while !Task.isCancelled {
            if previewNeedsTicks(id), let item = item(id) { item.tick(now: .now) }
            try? await Task.sleep(for: .seconds(settings.refreshSeconds))
        }
    }

    /// The scheduler ticks what's in the menu bar, and Overview there ticks its glyph's sources; a second tick
    /// would measure a sliver of a beat.
    func previewNeedsTicks(_ id: ItemID) -> Bool {
        if settings.isShown(id) { return false }
        return id == .overview || !(settings.isShown(.overview) && OverviewItem.sources(for: settings.overviewGlyphMetrics).contains(id))
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

/// A coloured glyph on a plain rounded tile, as in System Settings' sidebar on macOS 27. The glyph is fitted inside
/// the tile, so a wide symbol (the battery) shrinks rather than spilling out.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: symbol)
            .resizable()
            .symbolRenderingMode(.monochrome)
            .fontWeight(.semibold)
            .scaledToFit()
            .foregroundStyle(color.gradient)
            .frame(width: size * 0.62, height: size * 0.62)
            .frame(width: size, height: size)
            .background(tile.fill(.background))
            .overlay(tile.strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// Settings windows open in the preference toolbar style, title centred over the toolbar. System Settings uses the
/// unified style: the content runs under a transparent titlebar, and the page title sits beside back and forward.
private struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Hook() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Hook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.toolbarStyle = .unified
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
        }
    }
}

extension SettingsPane {
    /// Stored as the last page open, so Settings reopens where it was left, as System Settings does.
    var storageKey: String {
        switch self {
        case .general: "general"
        case .menuBar: "menuBar"
        case let .item(id): id.rawValue
        }
    }

    init?(storageKey: String?) {
        switch storageKey {
        case "general": self = .general
        case "menuBar": self = .menuBar
        case let raw?: guard let id = ItemID(rawValue: raw) else { return nil }; self = .item(id)
        case nil: return nil
        }
    }
}

/// The toolbar's back and forward: every page visited, and where in that list the window is.
struct PaneHistory: Equatable {
    private(set) var visited: [SettingsPane]
    private(set) var index = 0

    init(_ start: SettingsPane) { visited = [start] }

    var current: SettingsPane { visited[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < visited.count - 1 }

    /// A new page drops whatever was ahead, as in a browser.
    mutating func go(to pane: SettingsPane) {
        guard pane != current else { return }
        visited = Array(visited.prefix(index + 1)) + [pane]
        index += 1
    }

    mutating func back() { if canGoBack { index -= 1 } }
    mutating func forward() { if canGoForward { index += 1 } }
}

/// Laid out as System Settings: a full-height sidebar, back and forward beside the page title, and each
/// page an inset grouped form that leads with its live preview.
struct SettingsView: View {
    static let sidebarWidth: CGFloat = 240
    static let size = CGSize(width: 780, height: 640)
    let model: SettingsModel
    @State private var history: PaneHistory

    init(model: SettingsModel, pane: SettingsPane? = nil) {
        self.model = model
        _history = State(initialValue: PaneHistory(pane ?? model.lastPane ?? .general))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    row(.general)
                    row(.menuBar)
                }
                Section {
                    ForEach(SettingsPane.items, id: \.self) { row(.item($0)) }
                }
            }
            .listStyle(.sidebar)
            .environment(\.sidebarRowSize, .large)
            // The column width alone was ignored in offscreen renders; a minimum on the list holds it.
            .frame(minWidth: SettingsView.sidebarWidth)
            .navigationSplitViewColumnWidth(min: SettingsView.sidebarWidth, ideal: SettingsView.sidebarWidth,
                                            max: SettingsView.sidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(history.current)
                .formStyle(.grouped)
                .navigationTitle(history.current.title)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        ControlGroup {
                            Button { history.back() } label: { Label("Back", systemImage: "chevron.left") }
                                .disabled(!history.canGoBack)
                            Button { history.forward() } label: { Label("Forward", systemImage: "chevron.right") }
                                .disabled(!history.canGoForward)
                        }
                        .controlGroupStyle(.navigation)
                    }
                }
        }
        .frame(width: SettingsView.size.width)
        .frame(minHeight: 480, idealHeight: SettingsView.size.height)
        .background(SettingsWindowChrome())
        .onAppear { model.refreshLoginItem() }
        .onChange(of: history.current) { _, pane in model.lastPane = pane }
    }

    private var selection: Binding<SettingsPane?> {
        Binding(get: { history.current }, set: { if let pane = $0 { history.go(to: pane) } })
    }

    private func row(_ pane: SettingsPane) -> some View {
        Label { Text(pane.title) } icon: { pane.icon.sized(24) }
            .tag(pane)
    }

    @ViewBuilder private func detail(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPage(model: model)
        case .menuBar: MenuBarPage(model: model)
        case .item(.overview): OverviewPage(model: model)
        // A new identity per item, so the preview closes one panel and opens the next.
        case let .item(id): ItemPage(model: model, id: id).id(id)
        }
    }
}

private extension SettingsIcon {
    func sized(_ size: CGFloat) -> SettingsIcon { SettingsIcon(symbol: symbol, color: color, size: size) }
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

    var body: some View {
        Form {
            Section {
                MenuBarPreview(model: model)
            }
            Section {
                ReorderRows(model.order, move: model.move(fromOffsets:toOffset:)) { id in
                    SwitchRow(isOn: model.shown(id)) {
                        ReorderLabel(SettingsModel.title(id), icon: SettingsPane.item(id).icon)
                    }
                    .contextMenu {
                        Button("Move Up") { model.move(id, by: -1) }.disabled(!model.canMove(id, by: -1))
                        Button("Move Down") { model.move(id, by: 1) }.disabled(!model.canMove(id, by: 1))
                    }
                }
            } footer: {
                Text("Drag to reorder, or Command-drag in the menu bar.")
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

/// Rows that drag to reorder, with the system's insertion line. A grouped Form ignores onMove on macOS and its rows
/// never get drop callbacks, so these sit in a List of their own, sized to its rows, inside the form's section.
private struct ReorderRows<Item: Hashable, Row: View>: View {
    static var rowHeight: CGFloat { 40 }
    let items: [Item]
    let move: (IndexSet, Int) -> Void
    let row: (Item) -> Row

    init(_ items: [Item], move: @escaping (IndexSet, Int) -> Void, @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.move = move
        self.row = row
    }

    var body: some View {
        List {
            ForEach(items, id: \.self) { item in
                row(item)
                    .frame(height: Self.rowHeight)
                    .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, Self.rowHeight)
        .frame(height: CGFloat(items.count) * Self.rowHeight)
        .listRowInsets(EdgeInsets())
    }
}

/// The page's first group: the item's label and its real panel, live.
private struct PreviewSection: View {
    static let height: CGFloat = 300
    let model: SettingsModel
    let id: ItemID

    var body: some View {
        Section {
            ItemPreview(model: model, id: id)
                .frame(height: Self.height)
                .padding(.vertical, 6)
        }
    }
}

private struct OverviewPage: View {
    let model: SettingsModel

    /// The tile of the item a stat comes from; battery charge and system power read the Battery and Power items' tiles.
    static func icon(_ metric: OverviewMetric) -> SettingsIcon {
        let id: ItemID = metric.source ?? (metric == .battery ? .battery : .power)
        return SettingsPane.item(id).icon
    }

    var body: some View {
        Form {
            PreviewSection(model: model, id: .overview)
            Section {
                Toggle("Show in Menu Bar", isOn: model.shown(.overview))
            }
            Section {
                ReorderRows(model.glyphMetrics, move: model.moveGlyphMetrics(fromOffsets:toOffset:)) { metric in
                    // Only the switch goes dim at a limit; the row still drags.
                    SwitchRow(isOn: model.glyphShown(metric), isEnabled: model.canToggleGlyph(metric)) {
                        ReorderLabel(metric.title(in: .bars), icon: Self.icon(metric))
                    }
                    .contextMenu {
                        Button("Move Up") { model.moveGlyphMetric(metric, by: -1) }
                            .disabled(!model.canMoveGlyphMetric(metric, by: -1))
                        Button("Move Down") { model.moveGlyphMetric(metric, by: 1) }
                            .disabled(!model.canMoveGlyphMetric(metric, by: 1))
                    }
                }
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Up to \(OverviewMetric.glyphLimit) bars.")
            }
            Section("Panel") {
                Picker("Style", selection: model.overviewStyle) {
                    ForEach(OverviewStyle.allCases, id: \.self) { Text(SettingsModel.title($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                ReorderRows(model.overviewMetrics, move: model.moveMetrics(fromOffsets:toOffset:)) { metric in
                    SwitchRow(isOn: model.metricShown(metric)) {
                        ReorderLabel(metric.title(in: model.overviewStyle.wrappedValue), icon: Self.icon(metric))
                    }
                    .contextMenu {
                        Button("Move Up") { model.moveMetric(metric, by: -1) }.disabled(!model.canMoveMetric(metric, by: -1))
                        Button("Move Down") { model.moveMetric(metric, by: 1) }.disabled(!model.canMoveMetric(metric, by: 1))
                    }
                }
            } header: {
                Text("Contents")
            } footer: {
                Text("Drag to reorder, or Command-drag in the panel.")
            }
        }
    }
}

/// A form row's layout inside a plain List, where a Toggle would otherwise be a checkbox: label left, switch right.
private struct SwitchRow<Label: View>: View {
    let isOn: Binding<Bool>
    var isEnabled = true
    @ViewBuilder let label: Label

    var body: some View {
        HStack {
            label
            Spacer(minLength: 8)
            Toggle(isOn: isOn) { label }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!isEnabled)
        }
        .contentShape(Rectangle())
    }
}

/// A row title with a faint drag handle, and the item's icon where it has one.
private struct ReorderLabel: View {
    let title: String
    var icon: SettingsIcon?

    init(_ title: String, icon: SettingsIcon? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.quaternary)
                .accessibilityHidden(true)
            icon
            Text(title)
        }
    }
}

private struct ItemPage: View {
    let model: SettingsModel
    let id: ItemID

    var body: some View {
        Form {
            PreviewSection(model: model, id: id)
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
