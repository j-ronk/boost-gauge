import Charts
import SwiftUI

private struct HistoryPoint: Identifiable {
    let id: Int
    let segment: Int
    let date: Date
    let value: Double
}

struct GPUPanel: View {
    let model: GPUModel

    var body: some View {
        PanelChrome(footer: .activityMonitor) {
            PanelHeader(title: "GPU", subtitle: nil, bigValue: model.labelValue)
            PanelSection("Last 10 Minutes") {
                Chart(points) { p in
                    AreaMark(x: .value("Time", p.date), y: .value("Load", p.value), series: .value("Run", p.segment))
                        .foregroundStyle(.tint.opacity(0.2))
                    LineMark(x: .value("Time", p.date), y: .value("Load", p.value), series: .value("Run", p.segment))
                        .foregroundStyle(.tint)
                }
                .chartXScale(domain: xDomain)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel { if let p = value.as(Int.self) { Text("\(p)%") } }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 90)
                .accessibilityLabel("GPU load, last 10 minutes")
            }
            PanelSection("Details") {
                StatRow("Memory", model.memoryText)
                StatRow("Temperature", model.temperatureText)
                StatRow("Cores", model.coresText)
            }
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

    private var points: [HistoryPoint] {
        let maxGap = TimeInterval(max(3 * model.refreshSeconds, 10))
        var id = 0
        return GPUHistory.segments(model.history.points, maxGap: maxGap).enumerated().flatMap { segment, run in
            run.map { point in
                defer { id += 1 }
                return HistoryPoint(id: id, segment: segment, date: point.date, value: point.value)
            }
        }
    }

    private var xDomain: ClosedRange<Date> {
        let end = model.history.points.last?.date ?? .now
        return end.addingTimeInterval(-model.history.window)...end
    }
}
