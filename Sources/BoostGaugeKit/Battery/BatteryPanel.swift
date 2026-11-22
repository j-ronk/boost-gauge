import Charts
import SwiftUI

enum BatteryFormat {
    static func temperature(_ celsius: Double?, _ unit: TemperatureUnit) -> String {
        guard let celsius, celsius.isFinite else { return "—" }
        switch unit {
        case .celsius: return String(format: "%.1f °C", celsius)
        case .fahrenheit: return String(format: "%.1f °F", celsius * 9 / 5 + 32)
        }
    }
}

struct BatteryLabel: View {
    let model: BatteryModel
    let settings: AppSettings
    /// The status button's appearance, which follows the wallpaper under the menu bar, not the app's.
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let content = model.labelContent
        let tint = content.map {
            BatteryIcon.tint(percent: $0.percent, glyph: $0.glyph, lowPower: $0.lowPower, dark: scheme == .dark)
        } ?? .template
        Image(nsImage: BatteryIcon.label(percent: content?.percent ?? 0, glyph: content?.glyph ?? .none,
                                         showPercentage: settings.showBatteryPercentage && content != nil, tint: tint))
            .renderingMode(tint == .template ? .template : .original)
            .accessibilityLabel(content.map { "Battery \($0.percent)%" } ?? "Battery")
    }
}

struct BatteryPanel: View {
    let model: BatteryModel
    let ctx: AppContext

    var body: some View {
        let snapshot = model.snapshot
        PanelChrome(footer: .batterySettings) {
            PanelHeader(title: "Battery", subtitle: model.state?.headerText, bigValue: snapshot.map { "\($0.percent)%" })
            if let energyMode = ctx.energyMode {
                energyMode.makeSection()
            }
            HistorySection(model: model)
            PowerSection(snapshot: snapshot, fans: model.fans, history: model.powerHistory)
            PanelSection("Health") {
                StatRow("Maximum Capacity", model.healthPercent.map { "\($0)%" } ?? "—")
                StatRow("Cycle Count", snapshot.map { "\($0.cycleCount)" } ?? "—")
                StatRow("Temperature", BatteryFormat.temperature(snapshot?.temperatureC, ctx.settings.temperatureUnit))
            }
            UsingEnergySection(model: model)
        }
    }
}

struct HistorySection: View {
    @Bindable var model: BatteryModel

    var body: some View {
        PanelSection("History") {
            HistoryRangePicker(selection: $model.historyRange)
            HistoryChart(segments: model.historySegments, range: model.historyRange, now: model.historyNow)
        }
    }
}

struct HistoryRangePicker: View {
    @Binding var selection: HistoryRange

    var body: some View {
        CapsulePicker(title: "History Range", selection: Binding(get: { selection }, set: { if let r = $0 { selection = r } }),
                      options: HistoryRange.allCases.map { .init(value: $0, title: $0.title) },
                      height: 20, fillsWidth: false)
            .font(.callout)
    }
}

struct HistoryChart: View {
    let segments: [[ChargeSample]]
    let range: HistoryRange
    let now: Date

    private struct Point: Identifiable {
        let id: Int
        let segment: Int
        let isolated: Bool
        let sample: ChargeSample
    }

    // Positional ids: a seeded and a live sample can share a timestamp.
    private var points: [Point] {
        segments.enumerated()
            .flatMap { i, segment in segment.map { (i, segment.count == 1, $0) } }
            .enumerated()
            .map { Point(id: $0.offset, segment: $0.element.0, isolated: $0.element.1, sample: $0.element.2) }
    }

    var body: some View {
        Chart(points) { p in
            // One series per segment, so a sleep gap breaks the line instead of drawing straight across it.
            AreaMark(x: .value("Time", p.sample.date),
                     yStart: .value("Base", 0),
                     yEnd: .value("Charge", p.sample.percent),
                     series: .value("Segment", p.segment))
                .foregroundStyle(.tint.opacity(0.2))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", p.sample.date), y: .value("Charge", p.sample.percent),
                     series: .value("Segment", p.segment))
                .interpolationMethod(.monotone)
            // A lone reading between two gaps has no line to sit on, so it would otherwise vanish.
            if p.isolated {
                PointMark(x: .value("Time", p.sample.date), y: .value("Charge", p.sample.percent))
                    .symbolSize(12)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: now.addingTimeInterval(-range.span)...now)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { v in
                AxisGridLine()
                AxisValueLabel { if let p = v.as(Int.self) { Text("\(p)%") } }
            }
        }
        .chartXAxis {
            switch range {
            case .day:
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            case .tenDays:
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .frame(height: 70)
        .accessibilityLabel(range == .day ? "Charge over the last 24 hours" : "Charge over the last 10 days")
    }
}

struct UsingEnergySection: View {
    let model: BatteryModel

    var body: some View {
        PanelSection("Using Energy") {
            if !model.usersLoaded {
                Text("Loading…").foregroundStyle(.tertiary)
            } else if model.users.isEmpty {
                Text("No Apps Using Significant Energy").foregroundStyle(.secondary)
            }
            ForEach(model.users) { user in
                HStack(spacing: 8) {
                    Image(nsImage: user.icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(user.name).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f", user.impact))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        // `top` is the expensive part, so it only runs while this panel is on screen.
        .refreshing(every: .seconds(5)) { await model.refreshUsers?() }
    }
}
