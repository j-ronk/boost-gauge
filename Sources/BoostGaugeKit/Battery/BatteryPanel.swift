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
            let charts = model.sampleCharts ?? ctx.charts
            if settings.isSectionShown(.batteryHistory) {
                ChargeSection(model: model, charts: charts, settings: settings)
            }
            PowerSection(snapshot: snapshot, fans: model.fans, charts: charts, settings: settings,
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

/// Charge on the shared range like every chart, plus Battery's own 10 Days from the history file. 24 Hours fills
/// the recorded line's gaps from that file, which pmset's log backfills, so it covers time the app wasn't running.
struct ChargeSection: View {
    @Bindable var model: BatteryModel
    let charts: ChartHistory
    let settings: AppSettings

    @Environment(\.chartRangeOverride) private var rangeOverride
    @Environment(\.chartNowOverride) private var nowOverride

    var body: some View {
        let shared = rangeOverride ?? settings.chartRange
        let selection: ChargeRange = model.showsTenDays ? .tenDays : .shared(shared)
        let series = charts(.batteryCharge)
        let _ = series.revision
        let now: Date
        let span: TimeInterval
        let gap: TimeInterval
        let runs: [[ChartPoint]]
        switch selection {
        case .tenDays:
            now = model.historyNow
            span = HistoryRange.tenDays.span
            gap = HistoryRange.tenDays.bucket * 3
            runs = Self.points(model.historySegments)
        case let .shared(range):
            now = nowOverride ?? Date.now
            span = range.span
            let slice = series.slice(range, now: now)
            gap = max(slice.spacing, Double(settings.refreshSeconds)) * ChartLayout.gapFactor
            runs = range == .day
                ? ChartLine.filled(slice.points, gap: gap, logged: Self.points(model.historySegments))
                : ChartLine.runs(slice.points, gap: gap)
        }
        let end = now.timeIntervalSinceReferenceDate
        return VStack(alignment: .leading, spacing: 6) {
            ChartHeading(title: "Charge") {
                ChargeRangePicker(selection: Binding(get: { selection }, set: { choice in
                    switch choice {
                    case .tenDays: model.showsTenDays = true
                    case let .shared(range):
                        model.showsTenDays = false
                        settings.chartRange = range
                    }
                }))
            }
            ChartPlot(lines: [ChartLine(name: "Charge", runs: runs)], start: end - span, end: end, scale: .percent,
                      ticks: ChartTime.ticks(from: now.addingTimeInterval(-span), to: now), gap: gap,
                      sources: [ChartSource("Charge", series, live: model.snapshot.map { Double($0.percent) })],
                      valueText: Format.percent, accessibilityLabel: "Charge, \(selection.title)")
        }
    }

    /// The store already splits its samples at sleep and quit gaps.
    static func points(_ segments: [[ChargeSample]]) -> [[ChartPoint]] {
        segments.map { segment in
            segment.map { ChartPoint(t: $0.date.timeIntervalSinceReferenceDate, avg: Float($0.percent), peak: Float($0.percent)) }
        }
    }
}

extension ChartLine {
    /// The recorded points' runs, with logged stretches wherever nothing was recorded. A logged stretch is joined to
    /// the recorded line beside it, but two recorded runs stay apart: their gap is real.
    static func filled(_ recorded: [ChartPoint], gap: TimeInterval, logged: [[ChartPoint]]) -> [[ChartPoint]] {
        var runs = runs(recorded, gap: gap).map { (points: $0, logged: false) }
        let times = recorded.map(\.t)
        for segment in logged {
            var run: [ChartPoint] = []
            for p in segment {
                if HistoryStore.near(p.t, in: times, within: gap) {
                    if !run.isEmpty { runs.append((run, true)) }
                    run = []
                } else {
                    run.append(p)
                }
            }
            if !run.isEmpty { runs.append((run, true)) }
        }
        runs.sort { $0.points[0].t < $1.points[0].t }
        // Dropping the covered logged points leaves up to `gap` either side; a logged bucket can add as much again.
        let join = 2 * max(gap, HistoryRange.day.bucket)
        var out: [(points: [ChartPoint], logged: Bool)] = []
        for run in runs {
            if let last = out.last, last.logged || run.logged, let a = last.points.last, run.points[0].t - a.t <= join {
                out[out.count - 1] = (last.points + run.points, run.logged)
            } else {
                out.append(run)
            }
        }
        return out.map(\.points)
    }
}

struct ChargeRangePicker: View {
    @Binding var selection: ChargeRange

    var body: some View {
        CapsulePicker(title: "Charge Range", selection: Binding(get: { selection }, set: { if let r = $0 { selection = r } }),
                      options: ChargeRange.all.map { .init(value: $0, title: $0.title) },
                      // Four ranges and the title fit the panel width only a little tighter than the shared three.
                      height: 20, fillsWidth: false, segmentPadding: 6)
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
