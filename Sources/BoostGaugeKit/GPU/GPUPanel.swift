import SwiftUI

struct GPUPanel: View {
    let model: GPUModel
    let settings: AppSettings
    let charts: ChartHistory

    var body: some View {
        PanelChrome(footer: .activityMonitor) {
            PanelHeader(title: "GPU", subtitle: nil, bigValue: model.labelValue)
            if settings.isSectionShown(.gpuChart) { chart }
            if settings.isSectionShown(.gpuDetails) {
                PanelSection("Details") {
                    StatRow("Memory", model.memoryText)
                    StatRow("Temperature", model.temperatureText)
                    StatRow("Cores", model.coresText)
                }
            }
            if settings.isSectionShown(.gpuTopApps) { topApps }
        }
    }

    private var chart: some View {
        MetricChart(title: "Usage", settings: settings, sources: [ChartSource("GPU", charts(.gpu), live: model.utilization)],
                    scale: .percent, valueText: Format.percent, accessibilityName: "GPU usage")
    }

    private var topApps: some View {
        PanelSection("Top Apps") {
            if let rows = model.topApps {
                if rows.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(rows) { row in
                    IconRow(icon: row.icon, name: row.name, value: Format.percent(row.percent))
                }
            } else {
                Text("Loading…").foregroundStyle(.tertiary)
            }
        }
    }
}
