import AppKit
import SwiftUI

/// The live panel: whichever style Settings picks, in the user's order. Cmd-drag reorders it.
struct OverviewLivePanel: View {
    let model: OverviewModel
    let settings: AppSettings

    var body: some View {
        let style = settings.overviewStyle
        OverviewPanel(model: model, style: style, metrics: settings.overviewMetrics(for: style),
                      showsTopProcesses: settings.isSectionShown(.cpuTopProcesses),
                      reorder: { settings.moveOverviewMetric($0, onto: $1) })
    }
}

/// The condensed panel in one of three styles: Bars, an expandable List, or Tiles.
struct OverviewPanel: View {
    let model: OverviewModel
    let style: OverviewStyle
    let metrics: [OverviewMetric]
    var showsTopProcesses = true
    /// Nil leaves the panel fixed, as in renders.
    var reorder: ((OverviewMetric, OverviewMetric) -> Void)?
    @State private var tracker = ReorderTracker()

    init(model: OverviewModel, style: OverviewStyle, metrics: [OverviewMetric]? = nil, showsTopProcesses: Bool = true,
         reorder: ((OverviewMetric, OverviewMetric) -> Void)? = nil) {
        self.model = model
        self.style = style
        self.metrics = metrics ?? style.metrics
        self.showsTopProcesses = showsTopProcesses
        self.reorder = reorder
    }

    var body: some View {
        let r = model.reading
        let drag = ReorderContext(tracker: tracker, reorder: reorder)
        PanelChrome(footer: .activityMonitor) {
            switch style {
            case .bars:
                PanelHeader(title: "Overview", subtitle: OverviewText.batteryStatus(r.battery), bigValue: nil)
                OverviewBars(r: r, metrics: metrics, drag: drag)
            case .list:
                OverviewList(model: model, metrics: metrics, showsTopProcesses: showsTopProcesses, drag: drag)
            case .tiles:
                PanelHeader(title: "Overview", subtitle: OverviewText.batteryStatus(r.battery), bigValue: nil)
                OverviewTiles(r: r, metrics: metrics, drag: drag)
            }
        }
        .coordinateSpace(.named(ReorderTracker.space))
    }
}

// MARK: - Cmd-drag reorder

/// Follows a Cmd-drag across the panel's rows or tiles. Each row registers its frame; the dragged one takes the
/// place of whichever it passes over, so the panel reorders live, as the Settings list does.
@MainActor @Observable final class ReorderTracker {
    static let space = "overview.reorder"
    private(set) var dragging: OverviewMetric?
    @ObservationIgnored var frames: [OverviewMetric: CGRect] = [:]
    /// Set for the rest of a reorder drag so the List row it ends on doesn't also open or close.
    @ObservationIgnored private(set) var suppressesTap = false
    @ObservationIgnored private var refused = false

    /// A drag that began without Command is left alone for its whole length.
    func changed(_ metric: OverviewMetric, at location: CGPoint, commandDown: Bool,
                 reorder: (OverviewMetric, OverviewMetric) -> Void) {
        if dragging == nil {
            guard !refused else { return }
            guard commandDown else { refused = true; return }
            dragging = metric
            suppressesTap = true
        }
        guard dragging == metric, let target = Self.target(at: location, in: frames, excluding: metric) else { return }
        reorder(metric, target)
    }

    func ended() {
        dragging = nil
        refused = false
        // The row's tap lands in this same event; clear after it.
        DispatchQueue.main.async { self.suppressesTap = false }
    }

    static func target(at location: CGPoint, in frames: [OverviewMetric: CGRect], excluding dragged: OverviewMetric) -> OverviewMetric? {
        frames.first { $0.key != dragged && $0.value.contains(location) }?.key
    }
}

struct ReorderContext {
    let tracker: ReorderTracker
    let reorder: ((OverviewMetric, OverviewMetric) -> Void)?
}

private struct Reorderable: ViewModifier {
    let metric: OverviewMetric
    let drag: ReorderContext

    func body(content: Content) -> some View {
        if let reorder = drag.reorder {
            let tracker = drag.tracker
            content
                .background {
                    if tracker.dragging == metric {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(0.08)).padding(-3)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ReorderTracker.space)) } action: {
                    tracker.frames[metric] = $0
                }
                .onDisappear { tracker.frames[metric] = nil }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named(ReorderTracker.space))
                        .onChanged { value in
                            tracker.changed(metric, at: value.location, commandDown: NSEvent.modifierFlags.contains(.command)) {
                                dragged, target in withAnimation(.snappy) { reorder(dragged, target) }
                            }
                        }
                        .onEnded { _ in tracker.ended() }
                )
        } else {
            content
        }
    }
}

private extension View {
    func reorderable(_ metric: OverviewMetric, _ drag: ReorderContext) -> some View {
        modifier(Reorderable(metric: metric, drag: drag))
    }
}

// MARK: - A · Bars

/// One flat run of lines, so a row keeps its identity, and its drag, when a reorder splits or rejoins the groups.
/// Headed by group while every group's metrics stay together; once a drag splits one, a plain list in that order.
private struct OverviewBars: View {
    let r: OverviewReading
    let metrics: [OverviewMetric]
    let drag: ReorderContext

    private enum Line: Hashable {
        case heading(OverviewMetric.Group)
        case divider(OverviewMetric.Group)
        case row(OverviewMetric)
    }

    var body: some View {
        let grouped = OverviewOrder.isGrouped(metrics)
        let lines = Self.lines(metrics, grouped: grouped)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element) { i, item in
                line(item, grouped: grouped)
                    .padding(.top, i == 0 ? 0 : Self.spacing(after: lines[i - 1], before: item))
            }
        }
    }

    private static func lines(_ metrics: [OverviewMetric], grouped: Bool) -> [Line] {
        guard grouped else { return metrics.map(Line.row) }
        var out: [Line] = []
        for section in OverviewOrder.sections(metrics) {
            guard let group = section.first?.group else { continue }
            if !out.isEmpty { out.append(.divider(group)) }
            out.append(.heading(group))
            out += section.map(Line.row)
        }
        return out
    }

    /// PanelSection's 6 between a heading and its rows, PanelChrome's 12 around a divider.
    private static func spacing(after previous: Line, before line: Line) -> CGFloat {
        if case .divider = line { return 12 }
        if case .divider = previous { return 12 }
        return 6
    }

    @ViewBuilder private func line(_ line: Line, grouped: Bool) -> some View {
        switch line {
        case let .heading(group):
            Text(Self.heading(group))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        case .divider:
            Divider()
        case let .row(metric):
            row(metric, grouped: grouped).reorderable(metric, drag)
        }
    }

    private static func heading(_ group: OverviewMetric.Group) -> String {
        switch group {
        case .usage: "Usage"
        case .temperatures: "Temperatures"
        case .power: "Power"
        }
    }

    /// Under a heading the label can be short; in a plain list a temperature has to say so.
    @ViewBuilder private func row(_ metric: OverviewMetric, grouped: Bool) -> some View {
        let unit = r.temperatureUnit
        let width: CGFloat = grouped ? 64 : 72
        switch metric {
        case .cpu: LevelRow("CPU", OverviewText.fraction(r.cpu), OverviewText.percent(r.cpu), width)
        case .gpu: LevelRow("GPU", OverviewText.fraction(r.gpu), OverviewText.percent(r.gpu), width)
        case .memory: LevelRow("Memory", OverviewText.fraction(r.memory?.usedPercent), OverviewText.memoryUsed(r.memory), width)
        case .disk:
            LevelRow("Disk", OverviewText.fraction(r.disk.flatMap(OverviewText.diskUsedPercent)), OverviewText.diskUsed(r.disk), width)
        case .cpuTemp:
            LevelRow(grouped ? "CPU" : "CPU Temp", OverviewText.temperatureFraction(r.temps.cpu),
                     OverviewText.temperature(r.temps.cpu, unit), width)
        case .gpuTemp:
            LevelRow(grouped ? "GPU" : "GPU Temp", OverviewText.temperatureFraction(r.temps.gpu),
                     OverviewText.temperature(r.temps.gpu, unit), width)
        case .batteryTemp:
            let celsius = r.temps.battery ?? r.battery?.temperatureC
            LevelRow(grouped ? "Battery" : "Batt. Temp", OverviewText.temperatureFraction(celsius),
                     OverviewText.temperature(celsius, unit), width)
        case .hottest:
            LevelRow("Hottest", OverviewText.temperatureFraction(r.temps.hottest), OverviewText.temperature(r.temps.hottest, unit), width)
        case .battery:
            LevelRow("Battery", OverviewText.fraction(r.battery.map { Double($0.percent) }), OverviewText.batteryPercent(r.battery), width)
        case .systemPower: StatRow("System", OverviewText.watts(r.systemWatts))
        case .network: StatRow("Network", "\(OverviewText.download(r.network, r.networkUnit)) \(OverviewText.upload(r.network, r.networkUnit))")
        }
    }
}

/// [label · track · value], the Bars style's row.
private struct LevelRow: View {
    let label: String
    let fraction: Double?
    let value: String
    let labelWidth: CGFloat

    init(_ label: String, _ fraction: Double?, _ value: String, _ labelWidth: CGFloat = 64) {
        self.label = label
        self.fraction = fraction
        self.value = value
        self.labelWidth = labelWidth
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(label).lineLimit(1).frame(width: labelWidth, alignment: .leading)
            LevelTrack(fraction: fraction, height: 6)
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 76, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// An accent-filled level over a faint track.
struct LevelTrack: View {
    let fraction: Double?
    let height: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Capsule()
            .fill(.primary.opacity(scheme == .dark ? 0.1 : 0.08))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    if let fraction, fraction > 0 {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(height, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - B · Expandable list

private struct OverviewList: View {
    let model: OverviewModel
    let metrics: [OverviewMetric]
    let showsTopProcesses: Bool
    let drag: ReorderContext

    var body: some View {
        let r = model.reading
        VStack(alignment: .leading, spacing: 6) {
            ForEach(metrics, id: \.self) { metric in
                let open = model.expanded.contains(metric)
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        guard !drag.tracker.suppressesTap else { return }
                        withAnimation(.snappy) { model.toggle(metric) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: open ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            Text(metric.title(in: .list)).lineLimit(1)
                            Spacer(minLength: 0)
                            Sparkline(values: model.sparks[metric] ?? [])
                                .frame(width: 48, height: 14)
                            Text(OverviewText.rowValue(metric, r))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(metric.title(in: .list))
                    .accessibilityValue(OverviewText.rowValue(metric, r))
                    .accessibilityHint(open ? "Collapse" : "Expand")
                    if open {
                        VStack(alignment: .leading, spacing: 6) { detail(metric, r) }
                            .padding(.leading, 18)
                            .padding(.top, 2)
                            .padding(.bottom, 4)
                    }
                }
                .reorderable(metric, drag)
            }
        }
    }

    @ViewBuilder private func detail(_ metric: OverviewMetric, _ r: OverviewReading) -> some View {
        let unit = r.temperatureUnit
        switch metric {
        case .cpu:
            CoresChart(cores: model.cores, height: 48, showsLegend: false)
            StatRow("Temperature", OverviewText.temperature(r.temps.cpu, unit))
            if showsTopProcesses {
                if let rows = model.topProcesses {
                    ForEach(rows.prefix(2)) { IconRow(icon: $0.icon, name: $0.name, value: Format.percent($0.percent)) }
                } else {
                    Text("Loading…").foregroundStyle(.tertiary)
                }
            }
        case .gpu:
            StatRow("Temperature", OverviewText.temperature(r.temps.gpu, unit))
        case .memory:
            StatRow("Used", r.memory.map { MemoryFormat.usedOfTotal(used: $0.usedBytes, total: $0.totalBytes) } ?? "—")
        case .hottest:
            StatRow("CPU", OverviewText.temperature(r.temps.cpu, unit))
            StatRow("GPU", OverviewText.temperature(r.temps.gpu, unit))
            StatRow("Battery", OverviewText.temperature(r.temps.battery ?? r.battery?.temperatureC, unit))
        case .cpuTemp, .gpuTemp, .batteryTemp:
            EmptyView()
        case .battery, .systemPower:
            StatRow("Status", OverviewText.batteryStatus(r.battery) ?? "—")
            StatRow("System", OverviewText.watts(r.systemWatts))
        case .network:
            StatRow("Download", r.network.map { NetworkCounters.rateText($0.down, unit: r.networkUnit) } ?? "—")
            StatRow("Upload", r.network.map { NetworkCounters.rateText($0.up, unit: r.networkUnit) } ?? "—")
        case .disk:
            StatRow("Free", OverviewText.diskFree(r.disk))
            StatRow("Used", OverviewText.diskUsed(r.disk))
        }
    }
}

/// A min-to-max line of recent values. Fewer than two values draws nothing.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let span = hi - lo == 0 ? 1 : hi - lo
            var path = Path()
            for (i, v) in values.enumerated() {
                let point = CGPoint(x: CGFloat(i) / CGFloat(values.count - 1) * size.width,
                                    y: 1 + (size.height - 2) * (1 - (v - lo) / span))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - C · Tiles

private struct OverviewTiles: View {
    let r: OverviewReading
    let metrics: [OverviewMetric]
    let drag: ReorderContext

    var body: some View {
        TileFlow(spacing: 8) {
            ForEach(metrics, id: \.self) { metric in
                tile(metric)
                    .reorderable(metric, drag)
                    .layoutValue(key: WideTile.self, value: metric == .network)
            }
        }
    }

    @ViewBuilder private func tile(_ metric: OverviewMetric) -> some View {
        let unit = r.temperatureUnit
        switch metric {
        case .cpu: Tile(caption: "CPU", symbol: "cpu", value: Text(OverviewText.percent(r.cpu)), fraction: OverviewText.fraction(r.cpu))
        case .gpu: Tile(caption: "GPU", symbol: "display", value: Text(OverviewText.percent(r.gpu)), fraction: OverviewText.fraction(r.gpu))
        case .memory:
            Tile(caption: "Memory", symbol: "memorychip", value: split(OverviewText.memoryUsed(r.memory)),
                 fraction: OverviewText.fraction(r.memory?.usedPercent))
        case .disk:
            Tile(caption: "Disk", symbol: "internaldrive", value: split(OverviewText.diskFree(r.disk), suffix: " free"),
                 fraction: OverviewText.fraction(r.disk.flatMap(OverviewText.diskUsedPercent)))
        case .hottest:
            Tile(caption: "Hottest", symbol: "thermometer.medium", value: Text(OverviewText.temperature(r.temps.hottest, unit)),
                 fraction: OverviewText.temperatureFraction(r.temps.hottest))
        case .cpuTemp:
            Tile(caption: "CPU Temp", symbol: "thermometer.medium", value: Text(OverviewText.temperature(r.temps.cpu, unit)),
                 fraction: OverviewText.temperatureFraction(r.temps.cpu))
        case .gpuTemp:
            Tile(caption: "GPU Temp", symbol: "thermometer.medium", value: Text(OverviewText.temperature(r.temps.gpu, unit)),
                 fraction: OverviewText.temperatureFraction(r.temps.gpu))
        case .batteryTemp:
            let celsius = r.temps.battery ?? r.battery?.temperatureC
            Tile(caption: "Batt. Temp", symbol: "thermometer.medium", value: Text(OverviewText.temperature(celsius, unit)),
                 fraction: OverviewText.temperatureFraction(celsius))
        case .battery:
            Tile(caption: "Battery", symbol: "battery.75percent", value: Text(OverviewText.batteryPercent(r.battery)),
                 fraction: OverviewText.fraction(r.battery.map { Double($0.percent) }))
        case .systemPower:
            Tile(caption: "System", symbol: "bolt", value: split(OverviewText.watts(r.systemWatts)), fraction: nil, showsTrack: false)
        case .network:
            Tile(caption: "Network", symbol: "arrow.up.arrow.down",
                 value: Text("\(OverviewText.download(r.network, r.networkUnit))\(small(" " + OverviewText.upload(r.network, r.networkUnit)))"),
                 fraction: nil, showsTrack: false)
        }
    }

    /// "7.8 GB" as a large number and a small unit.
    private func split(_ text: String, suffix: String = "") -> Text {
        guard let space = text.firstIndex(of: " ") else { return Text(text) }
        return Text("\(String(text[..<space]))\(small(String(text[space...]) + suffix))")
    }

    private func small(_ text: String) -> Text {
        Text(text).font(.system(size: 12)).fontWeight(.regular).foregroundStyle(.secondary)
    }
}

private struct WideTile: LayoutValueKey {
    static let defaultValue = false
}

/// Two columns filled in order, with a wide tile (Network) on a row of its own. Tiles in a row share its height.
/// A layout rather than a Grid, so a tile keeps its identity, and its drag, as a reorder moves it between rows.
private struct TileFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 268
        let heights = rowHeights(subviews, width: width)
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = OverviewOrder.tileRows(wide: subviews.map { $0[WideTile.self] })
        let heights = rowHeights(subviews, width: bounds.width)
        let column = (bounds.width - spacing) / 2
        var y = bounds.minY
        for (row, height) in zip(rows, heights) {
            for (k, index) in row.enumerated() {
                let width = subviews[index][WideTile.self] ? bounds.width : column
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(k) * (column + spacing), y: y),
                                      proposal: ProposedViewSize(width: width, height: height))
            }
            y += height + spacing
        }
    }

    private func rowHeights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        let column = (width - spacing) / 2
        return OverviewOrder.tileRows(wide: subviews.map { $0[WideTile.self] }).map { row in
            row.map { index in
                let w = subviews[index][WideTile.self] ? width : column
                return subviews[index].sizeThatFits(ProposedViewSize(width: w, height: nil)).height
            }.max() ?? 0
        }
    }
}

private struct Tile: View {
    let caption: String
    let symbol: String
    let value: Text
    let fraction: Double?
    var showsTrack = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(caption)
                Spacer(minLength: 0)
                Image(systemName: symbol)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            value
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if showsTrack {
                LevelTrack(fraction: fraction, height: 4).padding(.top, 3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(scheme == .dark ? 0.06 : 0.05)))
        .accessibilityElement(children: .combine)
    }
}
