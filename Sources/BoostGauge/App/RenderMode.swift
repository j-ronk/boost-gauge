import AppKit
import SwiftUI
import BoostGaugeKit

/// `BoostGauge --render <dir>`: offscreen PNGs of every label and panel in light and dark, then exit.
/// The terminal can't screenshot the menu bar here (no screen recording permission), so this is how layouts get checked.
@MainActor enum RenderMode {
    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render") else { return nil }
        let path = i + 1 < args.count ? args[i + 1] : "build/render"
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    static var isActive: Bool { outputDirectory != nil }

    /// Returns false if any PNG couldn't be written, so `run.sh --render` fails loudly instead of leaving gaps.
    static func run(_ ctx: AppContext, to dir: URL) async -> Bool {
        failures = 0
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("render: can't create \(dir.path): \(error)\n".utf8))
            return false
        }

        // Hidden items render too, and delta readers (CPU, network) need two ticks before they have a value.
        let items = ctx.scheduler.items
        if !items.isEmpty {
            for item in items { item.tick(now: .now) }
            try? await Task.sleep(for: .seconds(1))
            for item in items { item.tick(now: .now) }
        }

        if CommandLine.arguments.contains("--real-windows") {
            for page in SettingsFeature.renderPages(ctx) {
                await showRealWindow(page.view, "settings-\(page.name)-real", title: page.title, in: dir)
            }
            return failures == 0
        }

        for item in items {
            for variant in await item.renderVariants() {
                let base = "\(item.id.rawValue)-\(variant.name)"
                await save(menuBarStrip(variant.label), "\(base)-label", in: dir)
                if let panel = variant.panel { await save(panel, "\(base)-panel", in: dir) }
            }
        }
        for page in SettingsFeature.renderPages(ctx) {
            await saveWindow(page.view, "settings-\(page.name)", title: page.title, in: dir)
        }
        if let section = ctx.energyMode?.makeSection() {
            await save(section.padding().frame(width: 300), "energymode", in: dir)
        }
        await save(ControlSamples(), "controls", in: dir)
        await save(DemoPanel(), "demo-panel", in: dir)
        await save(menuBarStrip(DemoLabels()), "demo-labels", in: dir)
        for strip in OverviewItem.renderStrips() {
            await save(menuBarStrip(strip.view), "overview-menubar-\(strip.name)", in: dir)
        }
        return failures == 0
    }

    private static var failures = 0

    private static func menuBarStrip(_ label: some View) -> some View {
        label.padding(.horizontal, 8).frame(height: 24)
    }

    private static func save(_ view: some View, _ name: String, in dir: URL) async {
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let url = dir.appendingPathComponent("\(name)-\(suffix).png")
            guard let rep = await snapshot(view, scheme),
                  let png = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("render: \(name)-\(suffix) produced no image\n".utf8))
                failures += 1
                continue
            }
            do {
                try png.write(to: url)
                print(url.path)
            } catch {
                FileHandle.standardError.write(Data("render: \(url.path): \(error)\n".utf8))
                failures += 1
            }
        }
    }

    /// A view that owns its window's chrome (Settings: sidebar under the traffic lights, toolbar title) needs a real
    /// titled window. This one sits far off every screen and is never made key; its frame view draws the chrome too.
    private static func saveWindow(_ view: some View, _ name: String, title: String, in dir: URL) async {
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let url = dir.appendingPathComponent("\(name)-\(suffix).png")
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let controller = NSHostingController(rootView: view.environment(\.colorScheme, scheme))
            controller.sizingOptions = [.preferredContentSize]
            // The toolbar and title come from SwiftUI, as in a scene's own window.
            controller.sceneBridgingOptions = [.toolbars, .title]
            let window = OffscreenWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.isReleasedWhenClosed = false
            window.appearance = appearance
            window.title = title
            window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
            window.orderFront(nil)
            try? await Task.sleep(for: .milliseconds(900))
            // The frame view holds the titlebar, traffic lights and toolbar as well as the content.
            let frameView = window.contentView?.superview ?? window.contentView
            var written = false
            if let frameView, let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    written = (try? png.write(to: url)) != nil
                }
            }
            window.orderOut(nil)
            window.close()
            if written {
                print(url.path)
            } else {
                FileHandle.standardError.write(Data("render: \(name)-\(suffix) window capture failed\n".utf8))
                failures += 1
            }
        }
    }

    /// `--render <dir> --real-windows`: Settings pages in real on-screen windows, for the parts offscreen drawing
    /// misses (sidebar glass). Each window goes to the very back, is never key or main, and closes as soon as the
    /// shell reading stdout has captured it with `screencapture -l` (this process has no screen recording access).
    private static func showRealWindow(_ view: some View, _ name: String, title: String, in dir: URL) async {
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let url = dir.appendingPathComponent("\(name)-\(suffix).png")
            try? FileManager.default.removeItem(at: url)
            let controller = NSHostingController(rootView: view.environment(\.colorScheme, scheme))
            controller.sizingOptions = [.preferredContentSize]
            controller.sceneBridgingOptions = [.toolbars, .title]
            let window = BackgroundWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.title = title
            window.center()
            window.orderBack(nil)
            try? await Task.sleep(for: .milliseconds(700))
            FileHandle.standardOutput.write(Data("capture \(window.windowNumber) \(url.path)\n".utf8))
            var waited = 0
            while !FileManager.default.fileExists(atPath: url.path), waited < 40 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            // screencapture creates the file before it finishes writing.
            try? await Task.sleep(for: .milliseconds(150))
            window.orderOut(nil)
            window.close()
            if !FileManager.default.fileExists(atPath: url.path) {
                FileHandle.standardError.write(Data("render: \(name)-\(suffix) not captured\n".utf8))
                failures += 1
            }
        }
    }

    /// Hosts the view in an offscreen window and snapshots it. Unlike ImageRenderer this draws real AppKit-backed
    /// controls (buttons, segmented pickers, forms); only the glass material itself is missing.
    private static func snapshot(_ view: some View, _ scheme: ColorScheme) async -> NSBitmapImageRep? {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme))
        host.appearance = appearance
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return nil }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // Lets onAppear and .task state land before the snapshot.
        try? await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.contentView = nil
        return rep
    }
}

/// Fixed sample of the shared chrome, so the look can be checked before any item exists.
private struct DemoPanel: View {
    var body: some View {
        PanelChrome(footer: .url("Battery Settings…", URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)) {
            PanelHeader(title: "Battery", subtitle: "Charging · 0:42 to full", bigValue: "34%")
            PanelSection("Power", detail: "Power Adapter") {
                StatRow("System", Format.watts(88.24))
                StatRow("Battery", Format.signedWatts(16))
                StatRow("Adapter", "88.2 W of 94 W")
            }
            PanelSection("Menu Bar") {
                HStack(spacing: 12) {
                    StackedLabel(caption: "CPU", value: "21%", widest: "100%")
                    StackedLabel(top: "↑ 12K", bottom: "↓ 1.2M", widest: "↓ 999M")
                }
            }
        }
    }
}

/// Every stacked label at plausible values, side by side as they'd sit in the menu bar.
private struct DemoLabels: View {
    var body: some View {
        HStack(spacing: 10) {
            StackedLabel(caption: "CPU", value: "7%", widest: "100%")
            StackedLabel(caption: "CPU", value: "100%", widest: "100%")
            StackedLabel(caption: "GPU", value: "—", widest: "100%")
            StackedLabel(caption: "RAM", value: "82%", widest: "100%")
            StackedLabel(caption: "TEMP", value: "62°C", widest: "100°C")
            StackedLabel(top: "↑ 12K", bottom: "↓ 1.2M", widest: "↓ 999M")
            StackedLabel(caption: "SSD", value: "412G", widest: "9.9T")
            StackedLabel(caption: "POWER", value: "102W", widest: "188W")
        }
    }
}

/// Stays exactly where it's put: a titled window is otherwise pulled back onto a screen when ordered in.
private final class OffscreenWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Never takes focus: it can't become key or main, so it never pulls the app or the keyboard forward.
private final class BackgroundWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
