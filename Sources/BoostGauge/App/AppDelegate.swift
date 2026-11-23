import AppKit
import BoostGaugeKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Built before any scene so `BoostGaugeApp.body` and the delegate share one context.
    @MainActor static let context: AppContext = {
        let ctx = AppContext()
        Registry.registerAll(ctx)
        return ctx
    }()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let ctx = Self.context
        if let dir = RenderMode.outputDirectory {
            Task { @MainActor in
                exit(await RenderMode.run(ctx, to: dir) ? 0 : 1)
            }
            return
        }
        ctx.charts.startSaving()
        ctx.scheduler.start()
        ctx.slots.start()
        ctx.onLaunch?()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Render runs never loaded or recorded a real day, so they must not overwrite the saved one.
        guard !RenderMode.isActive else { return }
        Self.context.charts.save()
    }

    /// Launching Boost Gauge again while it runs lands here; Track E uses it to open Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.context.onReopen?()
        return false
    }
}
