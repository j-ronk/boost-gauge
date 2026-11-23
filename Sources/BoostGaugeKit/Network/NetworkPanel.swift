import SwiftUI

struct NetworkPanel: View {
    let item: NetworkItem

    var body: some View {
        PanelChrome(footer: .url("Network Settings…",
                                 URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!)) {
            PanelHeader(title: "Network", subtitle: item.connection?.service ?? "Not Connected", bigValue: nil)
            if settings.isSectionShown(.networkChart) {
                MetricChart(title: "Speed", settings: settings,
                            sources: [ChartSource("Down", item.charts(.networkDown), live: item.rate?.down),
                                      ChartSource("Up", item.charts(.networkUp), live: item.rate?.up)],
                            scale: .upward(floor: 10_000, label: axisLabel),
                            valueText: { NetworkCounters.rateText($0, unit: unit) }, accessibilityName: "Network speed")
            }
            if settings.isSectionShown(.networkConnection), let connection = item.connection {
                PanelSection("Connection") {
                    StatRow("Interface", connection.interface)
                    if let address = connection.address {
                        StatRow("IP Address", address)
                    }
                }
            }
        }
        .refreshing(every: .seconds(5)) { item.refreshPanel() }
    }

    private var settings: AppSettings { item.ctx.settings }

    private var unit: NetworkUnit { item.unit }

    private var axisLabel: (Double) -> String {
        let unit = unit
        return { $0 == 0 ? "0" : NetworkCounters.compact($0, unit: unit) }
    }
}
