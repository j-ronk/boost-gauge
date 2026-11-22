import Charts
import SwiftUI

struct CPUPanel: View {
    let model: CPUModel

    var body: some View {
        PanelChrome(footer: .activityMonitor) {
            PanelHeader(title: "CPU", subtitle: nil, bigValue: model.total.map(Format.percent) ?? "—")
            PanelSection("Cores") {
                Chart(model.cores) { core in
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
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 90)
                .accessibilityLabel("Per-core load")
            }
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
}
