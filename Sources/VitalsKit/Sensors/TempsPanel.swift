import SwiftUI

struct TempsPanel: View {
    let item: TempsItem

    var body: some View {
        PanelChrome(footer: .app("Activity Monitor…", bundleID: "com.apple.ActivityMonitor")) {
            PanelHeader(title: "Temperatures", subtitle: item.summary.hottest == nil ? nil : "Hottest sensor",
                        bigValue: item.summary.hottest.map(item.text))
            PanelSection("Sensors") {
                if rows.isEmpty {
                    Text("Unavailable").foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.name) { row in
                    StatRow(row.name, item.text(row.celsius))
                }
            }
            if !item.fans.isEmpty {
                PanelSection("Fans") {
                    ForEach(item.fans, id: \.index) { fan in
                        StatRow("Fan \(fan.index + 1)", SensorSummary.rpm(fan.rpm))
                    }
                }
            }
        }
        .refreshing(every: .seconds(3)) { item.refreshPanel() }
    }

    private var rows: [(name: String, celsius: Double)] {
        let s = item.summary
        return [("CPU", s.cpu), ("GPU", s.gpu), ("Battery", s.battery)]
            .compactMap { name, value in value.map { (name, $0) } }
    }
}
