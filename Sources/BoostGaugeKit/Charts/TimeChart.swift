import SwiftUI

/// The one chart's measurements, from the charts mockup: a 64 pt plot inside the panel's 268 pt content width,
/// labels in a 40 pt trailing column and a row of times underneath.
public enum ChartLayout {
    public static let plotHeight: CGFloat = 64
    static let top: CGFloat = 7
    static let axisWidth: CGFloat = 40
    static let timeRow: CGFloat = 18
    static var height: CGFloat { top + plotHeight + timeRow }
    /// About one drawn point per pixel column of the 228 pt plot.
    public static let columns = 240
    /// Lines further apart than this many of their own spacing have a gap between them.
    static let gapFactor = 2.5
}

/// One drawn line: its runs of points, broken wherever readings stopped.
struct ChartLine {
    var name: String
    var runs: [[ChartPoint]]

    /// Splits sorted points wherever two are more than `gap` seconds apart.
    static func runs(_ points: [ChartPoint], gap: TimeInterval) -> [[ChartPoint]] {
        var runs: [[ChartPoint]] = []
        for p in points {
            if let last = runs.last?.last, p.t - last.t <= gap {
                runs[runs.count - 1].append(p)
            } else {
                runs.append([p])
            }
        }
        return runs
    }

    /// The point nearest `t`, if one lies within `gap` of it.
    func value(near t: TimeInterval, within gap: TimeInterval) -> ChartPoint? {
        let nearest = runs.lazy.flatMap { $0 }.min { abs($0.t - t) < abs($1.t - t) }
        guard let nearest, abs(nearest.t - t) <= gap else { return nil }
        return nearest
    }
}

/// The vertical axis: its domain and the three labelled grid lines at the bottom, middle and top.
struct ChartScale: Equatable {
    var lo: Double
    var hi: Double
    var labels: [Tick]

    struct Tick: Equatable {
        var value: Double
        var text: String
    }

    static let percent = ChartScale(lo: 0, hi: 100, labels: [0, 50, 100].map { Tick(value: $0, text: "\(Int($0))%") })

    /// 0 to a round top above the highest value (and never below `floor`), so an idle reading doesn't fill the plot.
    static func upward(_ values: [Double], floor: Double, label: (Double) -> String) -> ChartScale {
        let top = nice(max(floor, values.max() ?? 0))
        return ChartScale(lo: 0, hi: top, labels: [0, top / 2, top].map { Tick(value: $0, text: label($0)) })
    }

    /// Tens of degrees around the readings, 20 or more apart so the middle line is a round number too.
    static func temperature(_ values: [Double]) -> ChartScale {
        let low = values.min() ?? 40, high = values.max() ?? 60
        var lo = ((low - 2) / 10).rounded(.down) * 10
        var hi = ((high + 2) / 10).rounded(.up) * 10
        if hi - lo < 20 { hi = lo + 20 }
        if Int(hi - lo) % 20 != 0 { lo -= 10 }
        lo = max(0, lo)
        if Int(hi - lo) % 20 != 0 { hi += 10 }
        return ChartScale(lo: lo, hi: hi, labels: [lo, (lo + hi) / 2, hi].map { Tick(value: $0, text: "\(Int($0))°") })
    }

    /// The next of 1, 2, 4, 6, 8 or 10 times a power of ten, so half of it is still a plain number.
    static func nice(_ x: Double) -> Double {
        guard x > 0, x.isFinite else { return 1 }
        let k = pow(10, (log10(x)).rounded(.down))
        let m = x / k
        let step = [1.0, 2, 4, 6, 8, 10].first { m <= $0 * (1 + 1e-9) } ?? 10
        return step * k
    }
}

enum ChartTime {
    struct Tick: Equatable {
        var t: TimeInterval
        var text: String
    }

    /// Three labels at round times for the span: minutes for 10 Min and 1 Hour, quarter days for 24 Hours,
    /// every third day for 10 Days. A label too near either end would run off the plot, so it's dropped.
    static func ticks(from start: Date, to end: Date, calendar: Calendar = .current, locale: Locale = .current) -> [Tick] {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return [] }
        let (component, step): (Calendar.Component, Int) =
            span <= 900 ? (.minute, 3) : span <= 7200 ? (.minute, 15) : span <= 108_000 ? (.hour, 6) : (.day, 3)
        var dates: [Date] = []
        var d = calendar.startOfDay(for: start)
        while d <= end {
            let f = d.timeIntervalSince(start) / span
            if f >= 0.05, f <= 0.95 { dates.append(d) }
            guard let next = calendar.date(byAdding: component, value: step, to: d) else { break }
            d = next
        }
        while dates.count > 3 {
            let headRoom = dates[0].timeIntervalSince(start), tailRoom = end.timeIntervalSince(dates[dates.count - 1])
            if headRoom < tailRoom { dates.removeFirst() } else { dates.removeLast() }
        }
        var style: Date.FormatStyle
        switch component {
        case .minute: style = Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)
        case .hour: style = Date.FormatStyle().hour()
        default: style = Date.FormatStyle().day().month(.abbreviated)
        }
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return dates.map { Tick(t: $0.timeIntervalSinceReferenceDate, text: $0.formatted(style)) }
    }

    /// The hover readout's time: "10:09 pm", or the day as well past a day.
    static func hoverText(_ t: TimeInterval, span: TimeInterval) -> String {
        let date = Date(timeIntervalSinceReferenceDate: t)
        return span > 108_000 ? date.formatted(.dateTime.day().month(.abbreviated).hour()) : date.formatted(.dateTime.hour().minute())
    }
}

/// The chart itself: grid, lines (accent with a soft fill, then grey dashed, then grey dotted), times, and a hover
/// hairline with the time and first series' value.
struct TimeChart: View {
    let lines: [ChartLine]
    let start: TimeInterval
    let end: TimeInterval
    let scale: ChartScale
    let ticks: [ChartTime.Tick]
    let gap: TimeInterval
    let valueText: (Double) -> String
    @Binding var hover: TimeInterval?
    @State private var width: CGFloat = 268

    static let dashes: [[CGFloat]] = [[], [4, 3], [1.2, 2.6]]

    var body: some View {
        Canvas { ctx, size in
            draw(in: &ctx, size: size)
        }
        .frame(height: ChartLayout.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onContinuousHover { phase in
            switch phase {
            case let .active(p):
                let pw = width - ChartLayout.axisWidth
                hover = p.x <= pw + 4 ? start + Double(min(max(p.x, 0), pw) / max(pw, 1)) * (end - start) : nil
            case .ended:
                hover = nil
            }
        }
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let pw = size.width - ChartLayout.axisWidth
        let top = ChartLayout.top, ph = ChartLayout.plotHeight
        let span = max(end - start, 1)
        func x(_ t: TimeInterval) -> CGFloat { CGFloat((t - start) / span) * pw }
        func y(_ v: Double) -> CGFloat {
            let f = (min(max(v, scale.lo), scale.hi) - scale.lo) / max(scale.hi - scale.lo, 1e-9)
            return top + ph * CGFloat(1 - f)
        }
        let label = Font.subheadline

        for tick in scale.labels {
            let gy = (y(tick.value) * 2).rounded() / 2 + 0.25
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: gy))
            grid.addLine(to: CGPoint(x: pw + 4, y: gy))
            ctx.stroke(grid, with: .color(.primary.opacity(0.13)), lineWidth: 0.5)
            ctx.draw(Text(tick.text).font(label).foregroundStyle(.secondary).monospacedDigit(),
                     at: CGPoint(x: pw + 8, y: y(tick.value)), anchor: .leading)
        }

        // The first series' fill sits under every line.
        if let first = lines.first {
            for run in first.runs where run.count > 1 {
                var area = Path()
                area.move(to: CGPoint(x: x(run[0].t), y: y(scale.lo)))
                for p in run { area.addLine(to: CGPoint(x: x(p.t), y: y(Double(p.avg)))) }
                area.addLine(to: CGPoint(x: x(run[run.count - 1].t), y: y(scale.lo)))
                area.closeSubpath()
                ctx.fill(area, with: .color(.accentColor.opacity(0.2)))
            }
        }
        for (k, line) in lines.enumerated().reversed() {
            let color: Color = k == 0 ? .accentColor : .secondary
            let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: Self.dashes[min(k, 2)])
            for run in line.runs {
                if run.count == 1, let p = run.first {
                    // A lone reading between two gaps has no line to sit on.
                    let r: CGFloat = 1.5
                    ctx.fill(Path(ellipseIn: CGRect(x: x(p.t) - r, y: y(Double(p.avg)) - r, width: 2 * r, height: 2 * r)),
                             with: .color(color))
                    continue
                }
                var path = Path()
                for (i, p) in run.enumerated() {
                    let pt = CGPoint(x: x(p.t), y: y(Double(p.avg)))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.stroke(path, with: .color(color), style: style)
            }
        }

        for tick in ticks {
            ctx.draw(Text(tick.text).font(label).foregroundStyle(.secondary),
                     at: CGPoint(x: x(tick.t), y: top + ph + 10), anchor: .center)
        }

        if let hover, let first = lines.first, let p = first.value(near: hover, within: gap) {
            let hx = x(p.t), hy = y(Double(p.avg))
            var hair = Path()
            hair.move(to: CGPoint(x: hx, y: top))
            hair.addLine(to: CGPoint(x: hx, y: top + ph))
            ctx.stroke(hair, with: .color(.primary.opacity(0.35)), lineWidth: 1)
            let dot = Path(ellipseIn: CGRect(x: hx - 3.5, y: hy - 3.5, width: 7, height: 7))
            ctx.fill(dot, with: .color(Color(nsColor: .windowBackgroundColor)))
            ctx.stroke(dot, with: .color(.accentColor), lineWidth: 2)
            let text = ctx.resolve(Text("\(ChartTime.hoverText(p.t, span: span)) · \(valueText(Double(p.avg)))")
                .font(label).foregroundStyle(.primary).monospacedDigit())
            let w = text.measure(in: CGSize(width: size.width, height: 18)).width + 14
            let bx = min(max(hx - w / 2, 0), max(pw - w, 0))
            let box = Path(roundedRect: CGRect(x: bx, y: top, width: w, height: 18), cornerRadius: 5)
            ctx.fill(box, with: .color(Color(nsColor: .windowBackgroundColor)))
            ctx.stroke(box, with: .color(.primary.opacity(0.16)), lineWidth: 0.5)
            ctx.draw(text, at: CGPoint(x: bx + w / 2, y: top + 9), anchor: .center)
        }
    }
}

/// A chart's heading row: the section title, and its range picker right-aligned on the same line.
struct ChartHeading<Accessory: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            accessory
        }
        .frame(minHeight: 20)
    }
}

/// Names and live values for a chart with two or more lines, each beside a swatch of its line style.
struct ChartLegend: View {
    struct Entry: Equatable {
        var name: String
        var value: String
    }

    let entries: [Entry]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(entries.indices, id: \.self) { k in
                HStack(spacing: 5) {
                    Canvas { ctx, size in
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: size.height / 2))
                        p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        ctx.stroke(p, with: .color(k == 0 ? .accentColor : .secondary),
                                   style: StrokeStyle(lineWidth: k == 0 ? 1.8 : 1.6, dash: TimeChart.dashes[min(k, 2)]))
                    }
                    .frame(width: 16, height: 6)
                    Text(entries[k].name).foregroundStyle(.secondary)
                    Text(entries[k].value).fontWeight(.medium).monospacedDigit()
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// The shared range picker: one choice for every panel, remembered.
struct ChartRangePicker: View {
    @Binding var selection: ChartRange

    var body: some View {
        CapsulePicker(title: "Chart Range", selection: Binding(get: { selection }, set: { if let r = $0 { selection = r } }),
                      options: ChartRange.allCases.map { .init(value: $0, title: $0.title) },
                      height: 20, fillsWidth: false, segmentPadding: 8)
            .font(.subheadline)
    }
}

extension EnvironmentValues {
    /// Pins every chart below to one range, for `--render`; nil follows the shared setting.
    @Entry var chartRangeOverride: ChartRange?
}

/// One line of a panel chart: a recorded series, its live reading for the legend, and how to show both.
struct ChartSource {
    var name: String
    var history: SeriesHistory
    var live: Double?
    /// Recorded values in display units (Fahrenheit), or nil to draw them as recorded.
    var convert: ((Double) -> Double)?
    /// The legend's live text where it says more than the plotted value (Battery's sign).
    var liveText: String?

    init(_ name: String, _ history: SeriesHistory, live: Double?, convert: ((Double) -> Double)? = nil,
         liveText: String? = nil) {
        self.name = name
        self.history = history
        self.live = live
        self.convert = convert
        self.liveText = liveText
    }
}

enum ChartScaleKind {
    case percent
    case upward(floor: Double, label: (Double) -> String)
    case temperature

    func resolve(_ values: [Double]) -> ChartScale {
        switch self {
        case .percent: .percent
        case let .upward(floor, label): .upward(values, floor: floor, label: label)
        case .temperature: .temperature(values)
        }
    }
}

/// A panel's chart section: heading with the shared range picker, the chart, and a legend with live values once
/// there are two or more lines. Every item's panel uses this, and so does each Settings preview.
struct MetricChart: View {
    let title: String
    let settings: AppSettings
    let sources: [ChartSource]
    let scale: ChartScaleKind
    let valueText: (Double) -> String
    var accessibilityName: String

    @Environment(\.chartRangeOverride) private var rangeOverride
    @State private var hover: TimeInterval?

    var body: some View {
        let range = rangeOverride ?? settings.chartRange
        let now = Date.now
        let end = now.timeIntervalSinceReferenceDate
        let refresh = Double(settings.refreshSeconds)
        var gaps: [TimeInterval] = []
        let lines: [ChartLine] = sources.map { source in
            _ = source.history.revision
            let slice = source.history.slice(range, now: now)
            var points = slice.points
            if let convert = source.convert {
                points = points.map { ChartPoint(t: $0.t, avg: Float(convert(Double($0.avg))), peak: Float(convert(Double($0.peak)))) }
            }
            let gap = max(slice.spacing, refresh) * ChartLayout.gapFactor
            gaps.append(gap)
            return ChartLine(name: source.name, runs: ChartLine.runs(points, gap: gap))
        }
        let gap = gaps.max() ?? refresh * ChartLayout.gapFactor
        let values = lines.flatMap { $0.runs.flatMap { $0.map { Double($0.avg) } } }
        VStack(alignment: .leading, spacing: 6) {
            ChartHeading(title: title) {
                ChartRangePicker(selection: Binding(get: { range }, set: { settings.chartRange = $0 }))
            }
            TimeChart(lines: lines, start: end - range.span, end: end, scale: scale.resolve(values),
                      ticks: ChartTime.ticks(from: now.addingTimeInterval(-range.span), to: now),
                      gap: gap, valueText: valueText, hover: $hover)
                .accessibilityElement()
                .accessibilityLabel("\(accessibilityName), \(range.title)")
                .accessibilityValue(legendEntries(lines: lines, gap: gap).map { "\($0.name) \($0.value)" }
                    .joined(separator: ", "))
            if sources.count > 1 {
                ChartLegend(entries: legendEntries(lines: lines, gap: gap))
            }
        }
    }

    /// Live readings, or the hovered moment's while the pointer is over the chart.
    private func legendEntries(lines: [ChartLine], gap: TimeInterval) -> [ChartLegend.Entry] {
        sources.indices.map { k in
            let value: Double?
            if let hover {
                value = lines[k].value(near: hover, within: gap).map { Double($0.avg) }
            } else {
                if let text = sources[k].liveText { return ChartLegend.Entry(name: sources[k].name, value: text) }
                value = sources[k].live.map { sources[k].convert?($0) ?? $0 }
            }
            return ChartLegend.Entry(name: sources[k].name, value: value.map(valueText) ?? "—")
        }
    }
}
