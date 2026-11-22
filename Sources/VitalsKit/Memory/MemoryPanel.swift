import SwiftUI

struct MemoryPanel: View {
    let model: MemoryModel

    var body: some View {
        PanelChrome(footer: .activityMonitor) {
            PanelHeader(title: "Memory", subtitle: nil, bigValue: model.labelValue)
            PanelSection("Usage") {
                StatRow("Used", model.stats.map { MemoryFormat.usedOfTotal(used: $0.usedBytes, total: $0.totalBytes) } ?? "—")
                StatRow("Pressure", model.pressure?.rawValue ?? "—")
                StatRow("Swap", model.swapBytes.map(MemoryFormat.gigabytes) ?? "—")
            }
            PanelSection("Top Apps") {
                if let rows = model.topApps {
                    ForEach(rows) { row in
                        IconRow(icon: row.icon, name: row.name, value: MemoryFormat.appSize(row.bytes))
                    }
                } else {
                    Text("Loading…").foregroundStyle(.tertiary)
                }
            }
        }
    }
}
