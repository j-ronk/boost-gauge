import SwiftUI

@MainActor @Observable final class PowerModel {
    var snapshot: BatterySnapshot?
    var fans: [FanReading] = []
    /// Render samples carry their own chart history; nil draws the live one.
    var charts: ChartHistory?
    init(snapshot: BatterySnapshot? = nil, fans: [FanReading] = [], charts: ChartHistory? = nil) {
        self.snapshot = snapshot
        self.fans = fans
        self.charts = charts
    }
}

/// System power draw as a stacked "POWER / 102W" label, for people who watch watts rather than charge.
@MainActor public final class PowerItem: BoostGaugeItem {
    public let id = ItemID.power
    private let model = PowerModel()
    private let settings: AppSettings
    private let charts: ChartHistory
    private let readFans: () -> [FanReading]
    private var panelOpen = false

    public convenience init(_ ctx: AppContext) {
        let source = FanSource()
        self.init(ctx, readFans: { source.read() })
    }

    init(_ ctx: AppContext, readFans: @escaping () -> [FanReading]) {
        settings = ctx.settings
        charts = ctx.charts
        self.readFans = readFans
    }

    public var label: AnyView { AnyView(PowerLabel(model: model)) }
    public var panel: AnyView { AnyView(PowerPanel(model: model, settings: settings, charts: charts)) }

    public func tick(now: Date) {
        if let s = BatteryReader.read() {
            model.snapshot = s
            charts.recordPower(s, at: now)
        }
        if panelOpen { readFansIfShown() }
    }

    public func panelDidOpen() {
        panelOpen = true
        readFansIfShown()
    }

    /// Fans sit in the Power section, so they aren't read while it's hidden.
    private func readFansIfShown() {
        let fans = settings.isSectionShown(.powerPower) ? readFans() : []
        if model.fans != fans { model.fans = fans }
    }

    public func panelDidClose() {
        panelOpen = false
        model.fans = []
    }

    public func renderVariants() async -> [RenderVariant] {
        var variants = [RenderVariant("live", label: label, panel: panel)]
        for sample in BatterySamples.all {
            let m = PowerModel(snapshot: sample.snapshot, fans: BatterySamples.fans, charts: BatterySamples.powerHistory(sample.snapshot, now: ChartSamples.now))
            let panel = PowerPanel(model: m, settings: settings, charts: charts)
            // Every range for every state would triple the renders; one state shows the ranges.
            variants += sample.name == BatterySamples.all[0].name
                ? RenderVariant.eachRange(sample.name, label: AnyView(PowerLabel(model: m)), panel: panel)
                : [RenderVariant(sample.name, label: AnyView(PowerLabel(model: m)), panel: AnyView(panel.chartRender(.tenMinutes)))]
        }
        return variants
    }
}

struct PowerLabel: View {
    let model: PowerModel
    var body: some View {
        StackedLabel(caption: "POWER", value: PowerRows.menuBarValue(model.snapshot), widest: "188W")
    }
}

struct PowerPanel: View {
    let model: PowerModel
    let settings: AppSettings
    let charts: ChartHistory
    var body: some View {
        PanelChrome(footer: .batterySettings) {
            PowerSection(snapshot: model.snapshot, fans: model.fans, charts: model.charts ?? charts, settings: settings,
                         showsRows: settings.isSectionShown(.powerPower), showsChart: settings.isSectionShown(.powerChart))
        }
    }
}
