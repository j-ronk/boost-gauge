import AppKit
import VitalsKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Built before any scene so `VitalsApp.body` and the delegate share one context.
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
        ctx.scheduler.start()
        ctx.slots.start()
        ctx.onLaunch?()
    }

    /// Launching Vitals again while it runs lands here; Track E uses it to open Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.context.onReopen?()
        return false
    }
}
