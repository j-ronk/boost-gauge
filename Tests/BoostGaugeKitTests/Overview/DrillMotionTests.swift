import AppKit
import SwiftUI
import Testing
@testable import BoostGaugeKit

@MainActor
struct DrillSlideTests {
    @Test func slidesByTheViewsOwnWidth() {
        let size = CGSize(width: 300, height: 900)
        #expect(DrillSlide(fraction: 1).effectValue(size: size).m31 == 300, "in from the trailing edge")
        #expect(DrillSlide(fraction: -1).effectValue(size: size).m31 == -300)
        #expect(DrillSlide(fraction: 0.5).effectValue(size: size).m31 == 150)
        #expect(DrillSlide(fraction: 0).effectValue(size: size).m31 == 0)
        var effect = DrillSlide(fraction: 0)
        effect.animatableData = -0.25
        #expect(effect.fraction == -0.25)
    }
}

/// Opens an offscreen window (far off every screen, never key), so it only runs on request:
/// `TEST_RUNNER_BG_MOTION=1 scripts/test.sh DrillMotionTests`.
@MainActor
struct DrillMotionTests {
    @MainActor @Observable final class Pushed { var on = false }

    struct Host: View {
        let pushed: Pushed
        let panel: AnyView
        var body: some View {
            ZStack(alignment: .topLeading) {
                if pushed.on {
                    OverviewDetail(id: .battery, panel: panel).transition(OverviewLivePanel.detailTransition)
                } else {
                    Color.clear.frame(width: 300, height: 200).transition(OverviewLivePanel.overviewTransition)
                }
            }
            .clipped()
        }
    }

    /// Rows an item adds mid-slide move with the rest of its panel instead of landing in place.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BG_MOTION"] != nil))
    func rowsAddedMidSlideMoveWithThePanel() async throws {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        let model = BatterySamples.model(BatterySamples.all[0])
        let users = model.users
        model.users = []
        model.usersLoaded = false
        model.refreshUsers = { [weak model] in
            try? await Task.sleep(for: .milliseconds(60))
            model?.users = users
            model?.usersLoaded = true
        }
        let pushed = Pushed()
        let host = NSHostingView(rootView: Host(pushed: pushed, panel: AnyView(BatteryPanel(model: model, ctx: ctx)))
            .environment(\.colorScheme, .light).background(Color.white))
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 300, height: 1400), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        try await Task.sleep(for: .milliseconds(300))
        withAnimation(.linear(duration: 1)) { pushed.on = true }

        var checked = 0
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(60))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            guard model.usersLoaded, let header = Self.leftEdge(rep, rows: Self.band(rep, from: 0.665, to: 0.69)),
                  let energy = Self.leftEdge(rep, rows: Self.band(rep, from: 0.79, to: 0.84)),
                  header > rep.pixelsWide / 10, header < rep.pixelsWide * 8 / 10 else { continue }
            // Bands: Battery's Health rows (Maximum Capacity) and its Using Energy rows, in the sample panel at 2x.
            // A layout change to that panel moves them. Mid-slide, the late rows line up with Health, not their final x.
            #expect(abs(energy - header) < rep.pixelsWide / 15, "Health rows at \(header) px, energy rows at \(energy) px")
            checked += 1
        }
        #expect(checked > 0, "no frame caught the slide with the rows in")
    }

    private static func band(_ rep: NSBitmapImageRep, from: Double, to: Double) -> Range<Int> {
        Int(Double(rep.pixelsHigh) * from)..<Int(Double(rep.pixelsHigh) * to)
    }

    /// The leftmost column with a drawn, non-white pixel in `rows`.
    private static func leftEdge(_ rep: NSBitmapImageRep, rows: Range<Int>) -> Int? {
        for x in 0..<rep.pixelsWide {
            // Not yet drawn reads as clear, not ink.
            for y in rows {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.5 else { continue }
                if c.brightnessComponent < 0.8 { return x }
            }
        }
        return nil
    }
}
