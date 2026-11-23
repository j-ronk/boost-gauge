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
        let settings = ctx.settings
        PanelChrome(footer: .batterySettings) {
            PanelHeader(title: "Battery", subtitle: model.state?.headerText, bigValue: snapshot.map { "\($0.percent)%" })
            if let energyMode = ctx.energyMode, settings.isSectionShown(.batteryEnergyMode) {
                energyMode.makeSection()
            }
            if settings.isSectionShown(.batteryHistory) {
                HistorySection(model: model)
            }
            PowerSection(snapshot: snapshot, fans: model.fans, charts: model.powerCharts ?? ctx.charts, settings: settings,
                         showsRows: settings.isSectionShown(.batteryPower), showsChart: settings.isSectionShown(.batteryPowerChart))
            if settings.isSectionShown(.batteryHealth) {
                PanelSection("Health") {
                    StatRow("Maximum Capacity", model.healthPercent.map { "\($0)%" } ?? "—")
                    StatRow("Cycle Count", snapshot.map { "\($0.cycleCount)" } ?? "—")
                    StatRow("Temperature", BatteryFormat.temperature(snapshot?.temperatureC, settings.temperatureUnit))
                }
            }
            // Hidden, it never appears, so `top` doesn't run at all.
            if settings.isSectionShown(.batteryUsingEnergy) {
                UsingEnergySection(model: model)
            }
        }
    }
}

/// Charge from the history file and pmset's log, so it covers time the app wasn't running. It keeps its own
/// 24 Hours / 10 Days in the spot where every other chart has the shared range.
struct HistorySection: View {
    @Bindable var model: BatteryModel
    @State private var hover: TimeInterval?

    var body: some View {
        let range = model.historyRange
        let now = model.historyNow
        let end = now.timeIntervalSinceReferenceDate
        VStack(alignment: .leading, spacing: 6) {
            ChartHeading(title: "Charge") {
                HistoryRangePicker(selection: $model.historyRange)
            }
            TimeChart(lines: [ChartLine(name: "Charge", runs: Self.runs(model.historySegments))],
                      start: end - range.span, end: end, scale: .percent,
                      ticks: ChartTime.ticks(from: now.addingTimeInterval(-range.span), to: now),
                      gap: range.bucket * 3, valueText: Format.percent, hover: $hover)
                .accessibilityElement()
                .accessibilityLabel(range == .day ? "Charge over the last 24 hours" : "Charge over the last 10 days")
        }
    }

    /// The store already splits its samples at sleep and quit gaps.
    static func runs(_ segments: [[ChargeSample]]) -> [[ChartPoint]] {
        segments.map { segment in
            segment.map { ChartPoint(t: $0.date.timeIntervalSinceReferenceDate, avg: Float($0.percent), peak: Float($0.percent)) }
        }
    }
}

struct HistoryRangePicker: View {
    @Binding var selection: HistoryRange

    var body: some View {
        CapsulePicker(title: "Charge Range", selection: Binding(get: { selection }, set: { if let r = $0 { selection = r } }),
                      options: HistoryRange.allCases.map { .init(value: $0, title: $0.title) },
                      height: 20, fillsWidth: false, segmentPadding: 8)
            .font(.subheadline)
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
