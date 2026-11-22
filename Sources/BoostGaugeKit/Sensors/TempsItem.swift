import Foundation
import Observation
import SwiftUI

@MainActor @Observable public final class TempsItem: BoostGaugeItem {
    public let id: ItemID = .temps
    let ctx: AppContext
    public private(set) var summary = TempSummary()
    public private(set) var fans: [FanReading] = []
    @ObservationIgnored private let readTemperatures: () -> [(name: String, celsius: Double)]
    @ObservationIgnored private let readFans: () -> [FanReading]

    public convenience init(_ ctx: AppContext) {
        let smc = SMC()
        let temperatures = TemperatureReader(smc: smc)
        self.init(ctx, readTemperatures: { temperatures.read() }, readFans: { smc.fans() })
    }

    init(_ ctx: AppContext, readTemperatures: @escaping () -> [(name: String, celsius: Double)],
         readFans: @escaping () -> [FanReading]) {
        self.ctx = ctx
        self.readTemperatures = readTemperatures
        self.readFans = readFans
    }

    public var label: AnyView { AnyView(TempsLabel(item: self)) }
    public var panel: AnyView { AnyView(TempsPanel(item: self)) }

    public func tick(now: Date) {
        summary = SensorSummary.summarize(readTemperatures())
    }

    /// Fan speeds only matter with the panel open, so they're read here rather than on the menu bar tick.
    func refreshPanel() {
        let fans = ctx.settings.isSectionShown(.tempsFans) ? readFans() : []
        if self.fans != fans { self.fans = fans }
    }

    var labelValue: String {
        summary.hottest.map { SensorSummary.format($0, ctx.settings.temperatureUnit) } ?? "—"
    }

    var labelWidest: String { SensorSummary.widest(ctx.settings.temperatureUnit) }

    func text(_ celsius: Double) -> String {
        SensorSummary.format(celsius, ctx.settings.temperatureUnit)
    }

    public func renderVariants() async -> [RenderVariant] {
        // A fanless Mac (MacBook Air) must show no fan rows; this Mac has fans, so that case is staged.
        let fanless = TempsItem(ctx, readTemperatures: {
            [("Tp01", 58.4), ("Tp05", 61.9), ("Tg05", 49.6), ("TB1T", 31.5)]
        }, readFans: { [] })
        fanless.tick(now: .now)
        return [
            RenderVariant("live", label: label, panel: panel),
            RenderVariant("fanless", label: fanless.label, panel: fanless.panel),
        ]
    }
}

struct TempsLabel: View {
    let item: TempsItem

    var body: some View {
        StackedLabel(caption: "TEMP", value: item.labelValue, widest: item.labelWidest)
    }
}
