import SwiftUI

struct MemoryPanel: View {
    let model: MemoryModel
    let settings: AppSettings
    let charts: ChartHistory

    var body: some View {
        PanelChrome(footer: .activityMonitor) {
            PanelHeader(title: "Memory", subtitle: nil, bigValue: model.labelValue)
            if settings.isSectionShown(.memoryChart) {
                MetricChart(title: "Usage", settings: settings,
                            sources: [ChartSource("Used", charts(.memoryUsed), live: model.stats?.usedPercent),
                                      ChartSource("Pressure", charts(.memoryPressure), live: model.pressurePercent)],
                            scale: .percent, valueText: Format.percent, accessibilityName: "Memory usage")
            }
            if settings.isSectionShown(.memoryUsage) {
                PanelSection("Details") {
                    StatRow("Used", model.stats.map { MemoryFormat.usedOfTotal(used: $0.usedBytes, total: $0.totalBytes) } ?? "—")
                    StatRow("Pressure", model.pressure?.rawValue ?? "—")
                    StatRow("Swap", model.swapBytes.map(MemoryFormat.gigabytes) ?? "—")
                }
            }
            if settings.isSectionShown(.memoryTopApps) {
                PanelSection("Top Apps") {
                    if let rows = model.topApps {
                        ForEach(rows) { row in
                            IconRow(icon: row.icon, name: row.name, value: MemoryFormat.appSize(row.bytes))
                        }
                    } else {
                        Text("Loading…").foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
