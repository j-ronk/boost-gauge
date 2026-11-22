import Charts
import SwiftUI

struct NetworkPanel: View {
    let item: NetworkItem

    var body: some View {
        PanelChrome(footer: .url("Network Settings…",
                                 URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!)) {
            PanelHeader(title: "Network", subtitle: item.connection?.service ?? "Not Connected", bigValue: nil)
            PanelSection("Speed") {
                StatRow("Up", item.rate.map { NetworkCounters.rateText($0.up, unit: item.unit) } ?? "—")
                StatRow("Down", item.rate.map { NetworkCounters.rateText($0.down, unit: item.unit) } ?? "—")
            }
            PanelSection("Last 10 Minutes") {
                chart
            }
            if let connection = item.connection {
                PanelSection("Connection") {
                    StatRow("Interface", connection.interface)
                    if let address = connection.address {
                        StatRow("IP Address", address)
                    }
                }
            }
        }
        .refreshing(every: .seconds(5)) { item.refreshPanel() }
    }

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let series: String
        var id: String { "\(series)-\(date.timeIntervalSinceReferenceDate)" }
    }

    private var points: [Point] {
        item.down.points.map { Point(date: $0.date, value: $0.value, series: "Down") }
            + item.up.points.map { Point(date: $0.date, value: $0.value, series: "Up") }
    }

    /// A floor of 10 KB/s keeps an idle link from producing an axis of repeated "1K" labels.
    private var yMax: Double {
        max(10_000, (points.map(\.value).max() ?? 0) * 1.1)
    }

    private var chart: some View {
        Chart(points) { p in
            LineMark(x: .value("Time", p.date), y: .value("Rate", p.value))
                .foregroundStyle(by: .value("Direction", p.series))
                .lineStyle(by: .value("Direction", p.series))
        }
        // Colour alone never tells the lines apart: Up is also dashed, and the legend names both.
        .chartForegroundStyleScale(["Down": Color.accentColor, "Up": Color.secondary])
        .chartLineStyleScale(["Down": StrokeStyle(lineWidth: 1.5), "Up": StrokeStyle(lineWidth: 1.5, dash: [3, 2])])
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(NetworkCounters.compact(v, unit: item.unit)) }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 90)
    }
}
