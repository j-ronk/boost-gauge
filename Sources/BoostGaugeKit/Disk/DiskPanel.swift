import SwiftUI

struct DiskPanel: View {
    let item: DiskItem

    var body: some View {
        PanelChrome(footer: .app("Disk Utility…", bundleID: "com.apple.DiskUtility")) {
            PanelHeader(title: item.capacity?.name ?? "Disk", subtitle: item.capacity == nil ? nil : "Available",
                        bigValue: item.capacity.map { DiskStats.size($0.available) })
            if settings.isSectionShown(.diskChart) {
                MetricChart(title: "Activity", settings: settings,
                            sources: [ChartSource("Read", item.charts(.diskRead), live: item.activity?.read),
                                      ChartSource("Write", item.charts(.diskWrite), live: item.activity?.write)],
                            scale: .upward(floor: 1_000_000, label: { $0 == 0 ? "0" : NetworkCounters.compact($0) }),
                            valueText: { NetworkCounters.rateText($0, unit: .bytes) }, accessibilityName: "Disk activity")
            }
            if settings.isSectionShown(.diskStorage), let capacity = item.capacity, capacity.total > 0 {
                PanelSection("Storage") {
                    let used = max(0, capacity.total - capacity.available)
                    ProgressView(value: Double(used), total: Double(capacity.total))
                        .accessibilityLabel("Used")
                    StatRow("Used", DiskStats.size(used))
                    StatRow("Capacity", DiskStats.size(capacity.total))
                }
            }
        }
    }

    private var settings: AppSettings { item.ctx.settings }
}
