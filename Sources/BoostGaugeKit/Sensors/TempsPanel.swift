import SwiftUI

struct TempsPanel: View {
    let item: TempsItem
    /// Past this the sensor list scrolls, so a fully opened panel never runs off a laptop screen.
    var maxSensorsHeight: CGFloat = 520

    var body: some View {
        PanelChrome(footer: .app("Activity Monitor…", bundleID: "com.apple.ActivityMonitor")) {
            PanelHeader(title: "Temperatures", subtitle: item.summary.hottest == nil ? nil : "Hottest sensor",
                        bigValue: item.summary.hottest.map(item.text))
            if settings.isSectionShown(.tempsChart) {
                MetricChart(title: "Temperature", settings: settings,
                            sources: [ChartSource("Hottest", item.charts(.tempsHottest), live: item.summary.hottest, convert: convert),
                                      ChartSource("CPU", item.charts(.tempsCPU), live: item.summary.cpu, convert: convert),
                                      ChartSource("GPU", item.charts(.tempsGPU), live: item.summary.gpu, convert: convert)],
                            scale: .temperature, valueText: degrees, accessibilityName: "Temperatures")
            }
            if anyGroupSectionShown {
                PanelSection("Sensors") {
                    if shownGroups.isEmpty {
                        Text(item.hasReadGroups ? "Unavailable" : " ").foregroundStyle(.secondary)
                    } else {
                        CappedScroll(maxHeight: maxSensorsHeight) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(shownGroups, id: \.group) { reading in
                                    TempGroupRows(item: item, reading: reading)
                                }
                            }
                        }
                    }
                }
            }
            if settings.isSectionShown(.tempsFans), !item.fans.isEmpty {
                PanelSection("Fans") {
                    ForEach(item.fans, id: \.index) { fan in
                        StatRow("Fan \(fan.index + 1)", SensorSummary.rpm(fan.rpm))
                    }
                }
            }
        }
        .refreshing(every: .seconds(3)) { item.refreshPanel() }
    }

    private var settings: AppSettings { item.ctx.settings }

    /// The chart draws in the unit the rest of the panel shows.
    private var convert: ((Double) -> Double)? {
        settings.temperatureUnit == .fahrenheit ? { $0 * 9 / 5 + 32 } : nil
    }

    private var degrees: (Double) -> String {
        let suffix = settings.temperatureUnit == .fahrenheit ? "°F" : "°C"
        return { "\(Int($0.rounded()))\(suffix)" }
    }

    private var shownGroups: [TempGroupReading] {
        item.groups.filter { settings.isSectionShown($0.group.section) }
    }

    private var anyGroupSectionShown: Bool {
        TempGroup.allCases.contains { settings.isSectionShown($0.section) }
    }
}

/// The group's average as one row; opened, every sensor indented beneath it, led by the hottest in a long group.
private struct TempGroupRows: View {
    let item: TempsItem
    let reading: TempGroupReading

    var body: some View {
        if item.isExpandable(reading), let average = reading.average {
            Button {
                withAnimation(.snappy(duration: 0.2)) { item.toggleExpanded(reading) }
            } label: {
                HStack(spacing: 6) {
                    Text(reading.group.title)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Spacer()
                    Text(item.text(average))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(reading.group.title), average \(item.text(average))")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint("\(reading.sensors.count) sensors")
            if expanded {
                Group {
                    if reading.sensors.count > TempsItem.collapseThreshold, let hottest = reading.hottest {
                        StatRow("Hottest", item.text(hottest.celsius))
                    }
                    ForEach(reading.sensors, id: \.name) { sensor in
                        StatRow(sensor.name, item.text(sensor.celsius))
                    }
                }
                .font(.callout)
                .padding(.leading, 14)
            }
        } else if let sensor = reading.sensors.first {
            // One sensor: named for its group ("SSD", "Wi-Fi"), so no disclosure.
            StatRow(reading.group.title, item.text(sensor.celsius))
        }
    }

    private var expanded: Bool { item.isExpanded(reading) }
}

/// Content at its natural height up to `maxHeight`, scrolling past it.
private struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        CapHeight(maxHeight: maxHeight) {
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Asks its one child for its ideal height (a ScrollView's is its content's) and caps it.
private struct CapHeight: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: min(ideal.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
