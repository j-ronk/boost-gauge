import SwiftUI

/// The live panel: whichever style Settings picks.
struct OverviewLivePanel: View {
    let model: OverviewModel
    let settings: AppSettings

    var body: some View {
        OverviewPanel(model: model, style: settings.overviewStyle, showsTopProcesses: settings.isSectionShown(.cpuTopProcesses))
    }
}

/// The condensed panel in one of three styles: Bars, an expandable List, or Tiles.
struct OverviewPanel: View {
    let model: OverviewModel
    let style: OverviewStyle
    var showsTopProcesses = true

    var body: some View {
        let r = model.reading
        PanelChrome(footer: .activityMonitor) {
            switch style {
            case .bars:
                PanelHeader(title: "Overview", subtitle: OverviewText.batteryStatus(r.battery), bigValue: nil)
                OverviewBars(r: r)
            case .list:
                OverviewList(model: model, showsTopProcesses: showsTopProcesses)
            case .tiles:
                PanelHeader(title: "Overview", subtitle: OverviewText.batteryStatus(r.battery), bigValue: nil)
                OverviewTiles(r: r)
            }
        }
    }
}

// MARK: - A · Bars

/// Returned as separate sections so `PanelChrome` rules them off.
private struct OverviewBars: View {
    let r: OverviewReading

    var body: some View {
        PanelSection("Usage") {
            LevelRow("CPU", OverviewText.fraction(r.cpu), OverviewText.percent(r.cpu))
            LevelRow("GPU", OverviewText.fraction(r.gpu), OverviewText.percent(r.gpu))
            LevelRow("Memory", OverviewText.fraction(r.memory?.usedPercent), OverviewText.memoryUsed(r.memory))
            LevelRow("Disk", OverviewText.fraction(r.disk.flatMap(OverviewText.diskUsedPercent)), OverviewText.diskUsed(r.disk))
        }
        PanelSection("Temperatures") {
            temperature("CPU", r.temps.cpu)
            temperature("GPU", r.temps.gpu)
            temperature("Battery", r.temps.battery ?? r.battery?.temperatureC)
        }
        PanelSection("Power") {
            LevelRow("Battery", OverviewText.fraction(r.battery.map { Double($0.percent) }), OverviewText.batteryPercent(r.battery))
            StatRow("System", OverviewText.watts(r.systemWatts))
            StatRow("Network", "\(OverviewText.download(r.network, r.networkUnit)) \(OverviewText.upload(r.network, r.networkUnit))")
        }
    }

    private func temperature(_ label: String, _ celsius: Double?) -> LevelRow {
        LevelRow(label, OverviewText.temperatureFraction(celsius), OverviewText.temperature(celsius, r.temperatureUnit))
    }
}

/// [label · track · value], the Bars style's row.
private struct LevelRow: View {
    let label: String
    let fraction: Double?
    let value: String

    init(_ label: String, _ fraction: Double?, _ value: String) {
        self.label = label
        self.fraction = fraction
        self.value = value
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(label).lineLimit(1).frame(width: 64, alignment: .leading)
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
    let showsTopProcesses: Bool

    var body: some View {
        let r = model.reading
        VStack(alignment: .leading, spacing: 6) {
            ForEach(OverviewRow.allCases, id: \.self) { row in
                let open = model.expanded.contains(row)
                Button {
                    withAnimation(.snappy) { model.toggle(row) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        Text(row.title).lineLimit(1)
                        Spacer(minLength: 0)
                        Sparkline(values: model.sparks[row] ?? [])
                            .frame(width: 48, height: 14)
                        Text(OverviewText.rowValue(row, r))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.title)
                .accessibilityValue(OverviewText.rowValue(row, r))
                .accessibilityHint(open ? "Collapse" : "Expand")
                if open {
                    VStack(alignment: .leading, spacing: 6) { detail(row, r) }
                        .padding(.leading, 18)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    @ViewBuilder private func detail(_ row: OverviewRow, _ r: OverviewReading) -> some View {
        let unit = r.temperatureUnit
        switch row {
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
        case .temps:
            StatRow("CPU", OverviewText.temperature(r.temps.cpu, unit))
            StatRow("GPU", OverviewText.temperature(r.temps.gpu, unit))
            StatRow("Battery", OverviewText.temperature(r.temps.battery ?? r.battery?.temperatureC, unit))
        case .battery:
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

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Tile(caption: "CPU", symbol: "cpu", value: Text(OverviewText.percent(r.cpu)), fraction: OverviewText.fraction(r.cpu))
                Tile(caption: "GPU", symbol: "display", value: Text(OverviewText.percent(r.gpu)), fraction: OverviewText.fraction(r.gpu))
            }
            GridRow {
                Tile(caption: "Memory", symbol: "memorychip", value: split(OverviewText.memoryUsed(r.memory)),
                     fraction: OverviewText.fraction(r.memory?.usedPercent))
                Tile(caption: "Hottest", symbol: "thermometer.medium", value: Text(OverviewText.temperature(r.temps.hottest, r.temperatureUnit)),
                     fraction: OverviewText.temperatureFraction(r.temps.hottest))
            }
            GridRow {
                Tile(caption: "Battery", symbol: "battery.75percent", value: Text(OverviewText.batteryPercent(r.battery)),
                     fraction: OverviewText.fraction(r.battery.map { Double($0.percent) }))
                Tile(caption: "Disk", symbol: "internaldrive", value: split(OverviewText.diskFree(r.disk), suffix: " free"),
                     fraction: OverviewText.fraction(r.disk.flatMap(OverviewText.diskUsedPercent)))
            }
            GridRow {
                Tile(caption: "Network", symbol: "arrow.up.arrow.down",
                     value: Text("\(OverviewText.download(r.network, r.networkUnit))\(small(" " + OverviewText.upload(r.network, r.networkUnit)))"),
                     fraction: nil, showsTrack: false)
                    .gridCellColumns(2)
            }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(scheme == .dark ? 0.06 : 0.05)))
        .accessibilityElement(children: .combine)
    }
}
