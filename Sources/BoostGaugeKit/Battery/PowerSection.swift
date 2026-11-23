import SwiftUI

struct PowerRow: Equatable, Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

enum PowerRows {
    /// System, Battery and Adapter; a row with no reading is left out rather than shown as a dash.
    static func rows(_ s: BatterySnapshot) -> [PowerRow] {
        var rows: [PowerRow] = []
        if let load = s.systemLoadW { rows.append(PowerRow(label: "System", value: Format.watts(load))) }
        rows.append(PowerRow(label: "Battery", value: Format.signedWatts(s.batteryW)))
        rows += detailRows(s)
        return rows
    }

    /// What's left once System and Battery sit in the chart's legend: the adapter, while plugged in.
    static func detailRows(_ s: BatterySnapshot) -> [PowerRow] {
        guard s.onAC, let adapter = adapterValue(s) else { return [] }
        return [PowerRow(label: "Adapter", value: adapter)]
    }

    /// One row per fan; a fanless Mac has none, so the section shows nothing extra.
    static func fanRows(_ fans: [FanReading]) -> [PowerRow] {
        fans.map { PowerRow(label: "Fan \($0.index + 1)", value: SensorSummary.rpm($0.rpm)) }
    }

    private static func adapterValue(_ s: BatterySnapshot) -> String? {
        let rated = s.adapterRatedW.map { "\(Int($0.rounded())) W" }
        switch (s.adapterInW, rated) {
        case let (input?, rated?): return "\(Format.watts(input)) of \(rated)"
        case let (input?, nil): return Format.watts(input)
        case let (nil, rated?): return rated
        case (nil, nil): return nil
        }
    }

    /// The Power item's menu bar value: whole watts with no space, to fit the stacked label.
    static func menuBarValue(_ s: BatterySnapshot?) -> String {
        guard let load = s?.systemLoadW, load.isFinite else { return "—" }
        return "\(Int(load.rounded()))W"
    }
}

/// The Power chart (System and Battery watts, their live values in the legend), then Details: the adapter and fans.
struct PowerSection: View {
    let snapshot: BatterySnapshot?
    var fans: [FanReading] = []
    let charts: ChartHistory
    let settings: AppSettings
    var showsRows = true
    var showsChart = true

    var body: some View {
        if showsChart {
            MetricChart(title: "Power", settings: settings,
                        sources: [ChartSource("System", charts(.powerSystem), live: snapshot?.systemLoadW),
                                  ChartSource("Battery", charts(.powerBattery), live: snapshot.map { abs($0.batteryW) },
                                              liveText: snapshot.map { Format.signedWatts($0.batteryW) })],
                        scale: .upward(floor: 20, label: { "\(Int($0.rounded()))W" }),
                        valueText: Format.watts, accessibilityName: "Power")
        }
        let rows = (snapshot.map(PowerRows.detailRows) ?? []) + PowerRows.fanRows(fans)
        if showsRows, !rows.isEmpty {
            PanelSection("Details") {
                ForEach(rows) { StatRow($0.label, $0.value) }
            }
        }
    }
}

extension ChartHistory {
    /// Battery and Power share one beat, so both record into the same two series; the second write of a beat is
    /// dropped as a repeat.
    func recordPower(_ s: BatterySnapshot, at date: Date) {
        guard let load = s.systemLoadW, load.isFinite else { return }
        record(.powerSystem, load, at: date)
        record(.powerBattery, abs(s.batteryW), at: date)
    }

    /// Battery's beat: the shared power series, and charge, which only Battery charts.
    func recordBattery(_ s: BatterySnapshot, at date: Date) {
        recordPower(s, at: date)
        record(.batteryCharge, Double(s.percent), at: date)
    }
}

extension FooterButton {
    static var batterySettings: FooterButton {
        .url("Battery Settings…", URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
    }
}
