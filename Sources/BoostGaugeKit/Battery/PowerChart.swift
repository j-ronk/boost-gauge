import Charts
import SwiftUI

/// Ten minutes of System and Battery watts, fed from the item's tick while it is shown.
struct PowerHistory {
    var system = TimeSeries()
    var battery = TimeSeries()

    mutating func add(_ s: BatterySnapshot, at date: Date) {
        guard let load = s.systemLoadW, load.isFinite else { return }
        system.append(load, at: date)
        battery.append(abs(s.batteryW), at: date)
    }
}

struct PowerChart: View {
    let history: PowerHistory

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let series: String
        var id: String { "\(series)-\(date.timeIntervalSinceReferenceDate)" }
    }

    private var points: [Point] {
        history.system.points.map { Point(date: $0.date, value: $0.value, series: "System") }
            + history.battery.points.map { Point(date: $0.date, value: $0.value, series: "Battery") }
    }

    /// A floor of 20 W keeps an idle Mac from producing an axis of repeated "3W" labels.
    static func yMax(_ values: [Double]) -> Double {
        max(20, (values.max() ?? 0) * 1.1)
    }

    var body: some View {
        let pts = points
        Chart(pts) { p in
            LineMark(x: .value("Time", p.date), y: .value("Power", p.value))
                .foregroundStyle(by: .value("Series", p.series))
                .lineStyle(by: .value("Series", p.series))
        }
        .chartForegroundStyleScale(["System": Color.accentColor, "Battery": Color.secondary])
        .chartLineStyleScale(["System": StrokeStyle(lineWidth: 1.5), "Battery": StrokeStyle(lineWidth: 1.5, dash: [3, 2])])
        .chartYScale(domain: 0...Self.yMax(pts.map(\.value)))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v.rounded()))W") }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 90)
    }
}
