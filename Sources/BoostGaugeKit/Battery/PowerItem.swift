import SwiftUI

@MainActor @Observable final class PowerModel {
    var snapshot: BatterySnapshot?
    var fans: [FanReading] = []
    var history = PowerHistory()
    init(snapshot: BatterySnapshot? = nil, fans: [FanReading] = [], history: PowerHistory = PowerHistory()) {
        self.snapshot = snapshot
        self.fans = fans
        self.history = history
    }
}

/// System power draw as a stacked "POWER / 102W" label, for people who watch watts rather than charge.
@MainActor public final class PowerItem: BoostGaugeItem {
    public let id = ItemID.power
    private let model = PowerModel()
    private let readFans: () -> [FanReading]
    private var panelOpen = false

    public convenience init(_ ctx: AppContext) {
        let source = FanSource()
        self.init(ctx, readFans: { source.read() })
    }

    init(_ ctx: AppContext, readFans: @escaping () -> [FanReading]) {
        self.readFans = readFans
    }

    public var label: AnyView { AnyView(PowerLabel(model: model)) }
    public var panel: AnyView { AnyView(PowerPanel(model: model)) }

    public func tick(now: Date) {
        if let s = BatteryReader.read(includePack: false) {
            model.snapshot = s
            model.history.add(s, at: now)
        }
        if panelOpen { model.fans = readFans() }
    }

    public func panelDidOpen() {
        panelOpen = true
        model.fans = readFans()
    }

    public func panelDidClose() {
        panelOpen = false
        model.fans = []
    }

    public func renderVariants() async -> [RenderVariant] {
        var variants = [RenderVariant("live", label: label, panel: panel)]
        for sample in BatterySamples.all {
            let m = PowerModel(snapshot: sample.snapshot, fans: BatterySamples.fans, history: BatterySamples.powerHistory(sample.snapshot))
            variants.append(RenderVariant(sample.name, label: AnyView(PowerLabel(model: m)), panel: AnyView(PowerPanel(model: m))))
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
    var body: some View {
        PanelChrome(footer: .batterySettings) {
            PowerSection(snapshot: model.snapshot, fans: model.fans, history: model.history)
        }
    }
}
