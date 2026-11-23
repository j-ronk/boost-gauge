import Charts
import SwiftUI

struct CPUPanel: View {
    let model: CPUModel
    let settings: AppSettings
    let charts: ChartHistory

    var body: some View {
        PanelChrome(footer: .activityMonitor) {
            PanelHeader(title: "CPU", subtitle: nil, bigValue: model.total.map(Format.percent) ?? "—")
            if settings.isSectionShown(.cpuChart) {
                MetricChart(title: "Usage", settings: settings, sources: [ChartSource("CPU", charts(.cpu), live: model.total)],
                            scale: .percent, valueText: Format.percent, accessibilityName: "CPU usage")
            }
            if settings.isSectionShown(.cpuCores) { cores }
            if settings.isSectionShown(.cpuDetails) {
                PanelSection("Details") {
                    StatRow("Temperature", model.temperatureText)
                    StatRow("Hottest Sensor", model.hottestSensorText)
                    StatRow("Cores", model.coresText)
                }
            }
            if settings.isSectionShown(.cpuTopProcesses) { topProcesses }
        }
    }

    private var cores: some View {
        PanelSection("Cores") { CoresChart(cores: model.cores, height: 90, showsLegend: true) }
    }

    private var topProcesses: some View {
        PanelSection("Top Processes") {
            if let rows = model.topProcesses {
                if rows.isEmpty { Text("Idle").foregroundStyle(.secondary) }
                ForEach(rows) { row in
                    IconRow(icon: row.icon, name: row.name, value: Format.percent(row.percent))
                }
            } else {
                Text("Loading…").foregroundStyle(.tertiary)
            }
        }
    }
}

/// Per-core load bars, efficiency and performance cores in their own colours.
struct CoresChart: View {
    let cores: [CoreLoad]
    let height: CGFloat
    let showsLegend: Bool

    var body: some View {
        Chart(cores) { core in
            BarMark(x: .value("Core", "\(core.id + 1)"), y: .value("Load", core.percent))
                .foregroundStyle(by: .value("Type", core.kind.title))
        }
        .chartForegroundStyleScale(domain: [CoreKind.efficiency.title, CoreKind.performance.title])
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel { if let p = value.as(Int.self) { Text("\(p)%") } }
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(showsLegend ? .visible : .hidden)
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: height)
        .accessibilityLabel("Per-core load")
    }
}
