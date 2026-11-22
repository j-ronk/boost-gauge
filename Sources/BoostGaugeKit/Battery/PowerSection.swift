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
        if s.onAC, let adapter = adapterValue(s) { rows.append(PowerRow(label: "Adapter", value: adapter)) }
        return rows
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

struct PowerSection: View {
    let snapshot: BatterySnapshot?
    var fans: [FanReading] = []
    var history = PowerHistory()
    var showsRows = true
    var showsChart = true

    var body: some View {
        if showsRows {
            PanelSection("Power") {
                if let snapshot {
                    ForEach(PowerRows.rows(snapshot)) { StatRow($0.label, $0.value) }
                }
                ForEach(PowerRows.fanRows(fans)) { StatRow($0.label, $0.value) }
            }
        }
        if showsChart, history.system.points.count > 1 {
            PanelSection("Last 10 Minutes") { PowerChart(history: history) }
        }
    }
}

extension FooterButton {
    static var batterySettings: FooterButton {
        .url("Battery Settings…", URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
    }
}
