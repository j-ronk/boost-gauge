import SwiftUI

struct DiskPanel: View {
    let item: DiskItem
    var samplesLive = true

    var body: some View {
        PanelChrome(footer: .app("Disk Utility…", bundleID: "com.apple.DiskUtility")) {
            PanelHeader(title: item.capacity?.name ?? "Disk", subtitle: item.capacity == nil ? nil : "Available",
                        bigValue: item.capacity.map { DiskStats.size($0.available) })
            if let capacity = item.capacity, capacity.total > 0 {
                PanelSection("Storage") {
                    let used = max(0, capacity.total - capacity.available)
                    ProgressView(value: Double(used), total: Double(capacity.total))
                        .accessibilityLabel("Used")
                    StatRow("Used", DiskStats.size(used))
                    StatRow("Capacity", DiskStats.size(capacity.total))
                }
            }
            PanelSection("Activity") {
                StatRow("Read", item.activity.map { NetworkCounters.rateText($0.read, unit: .bytes) } ?? "—")
                StatRow("Write", item.activity.map { NetworkCounters.rateText($0.write, unit: .bytes) } ?? "—")
            }
        }
        .refreshing(every: .seconds(2)) {
            if samplesLive { item.sampleActivity(now: .now) }
        }
    }
}
