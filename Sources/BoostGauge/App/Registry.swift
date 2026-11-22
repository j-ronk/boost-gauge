import BoostGaugeKit

/// Each track owns exactly one slot line below and uncomments only that line, so parallel merges never conflict.
@MainActor enum Registry {
    static func registerAll(_ ctx: AppContext) {
        func add(_ item: any BoostGaugeItem) { ctx.scheduler.register(item) }

        // Slot A (Battery):
        add(BatteryItem(ctx)); add(PowerItem(ctx))
        //
        ctx.energyMode = EnergyModeController(ctx)  // Slot B (EnergyMode)
        //
        add(CPUItem(ctx)); add(GPUItem(ctx)); add(MemoryItem(ctx)) // Slot C (CPU/GPU/RAM)
        //
        add(TempsItem(ctx)); add(NetworkItem(ctx)); add(DiskItem(ctx)) // Slot D (Temps/Net/Disk)
        // Last: it ticks after the items it reads, and ticks the ones that are out of the menu bar itself.
        add(OverviewItem(ctx))
        //
        SettingsFeature.install(ctx) // Slot E (Settings)
    }
}
