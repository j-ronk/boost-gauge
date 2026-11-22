import AppKit
import Observation
import Testing
@testable import VitalsKit

/// A Low Power state the test sets, instead of the real ProcessInfo.
private final class FakeLowPower: @unchecked Sendable {
    var on = false
}

@MainActor
struct LowPowerIconTests {
    @Test func lowPowerIsPartOfTheKey() {
        let plain = BatteryIcon.label(percent: 47, glyph: .none, showPercentage: true)
        let darkLow = BatteryIcon.label(percent: 47, glyph: .none, showPercentage: true, tint: .lowPower(dark: true))
        let lightLow = BatteryIcon.label(percent: 47, glyph: .none, showPercentage: true, tint: .lowPower(dark: false))
        #expect(plain !== darkLow)
        #expect(darkLow !== lightLow)
        #expect(BatteryIcon.label(percent: 47, glyph: .none, showPercentage: true, tint: .lowPower(dark: true)) === darkLow)
        #expect(BatteryIcon.label(percent: 47, glyph: .none, showPercentage: true, tint: .template) === plain)
    }

    @Test func templateOnlyWhenNotColoured() {
        #expect(BatteryIcon.label(percent: 47, glyph: .none, showPercentage: true).isTemplate)
        #expect(!BatteryIcon.label(percent: 47, glyph: .none, showPercentage: true, tint: .lowPower(dark: true)).isTemplate)
        #expect(!BatteryIcon.label(percent: 47, glyph: .bolt, showPercentage: false, tint: .lowPower(dark: false)).isTemplate)
    }

    /// Like the system icon: the charge turns yellow; the empty part and the terminal keep the label colour.
    @Test func chargeIsYellowAndTheRestIsTheLabelColour() {
        for dark in [true, false] {
            let pixels = RGBA(BatteryIcon.label(percent: 50, glyph: .none, showPercentage: false, tint: .lowPower(dark: dark)))
            let body = BatteryIcon.bodyRect
            let charge = pixels.at(body.minX + 3, body.midY)
            let empty = pixels.at(body.maxX - 3, body.midY)
            let terminal = pixels.at(body.maxX + 1.6, body.midY)
            #expect(charge.isYellow, "charge \(charge) dark \(dark)")
            #expect(charge.a > 0.95)
            for part in [empty, terminal] {
                #expect(part.isNeutral, "\(part) dark \(dark)")
                #expect(dark ? part.r > 0.9 : part.r < 0.1, "\(part) dark \(dark)")
                #expect(part.a > 0.2 && part.a < 0.6, "\(part) dark \(dark)")
            }
        }
    }

    /// Same shape as the template: the digits still cut through and nothing is drawn outside the battery.
    @Test func colouredKeepsTheTemplateShape() {
        for (percent, glyph, show) in [(47, BatteryGlyph.none, true), (8, .none, true), (100, .plug, true), (34, .bolt, false)] {
            let template = Alpha(BatteryIcon.label(percent: percent, glyph: glyph, showPercentage: show))
            let coloured = Alpha(BatteryIcon.label(percent: percent, glyph: glyph, showPercentage: show, tint: .lowPower(dark: true)))
            #expect(template.width == coloured.width && template.height == coloured.height)
            // The label colour is translucent, so the faintest anti-aliased edge pixels can round to clear.
            let mismatched = zip(template.values, coloured.values).filter { min($0, $1) == 0 && max($0, $1) > 25 }.count
            #expect(mismatched == 0, "\(percent) \(glyph)")
        }
    }
}

@MainActor
struct LowPowerMonitorTests {
    @Test func readsAtStartAndOnTheNotification() async throws {
        let fake = FakeLowPower()
        fake.on = true
        let center = NotificationCenter()
        let monitor = LowPowerMonitor(read: { fake.on }, center: center)
        #expect(monitor.isOn)
        fake.on = false
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        var i = 0
        while monitor.isOn, i < 50 {
            try await Task.sleep(for: .milliseconds(20))
            i += 1
        }
        #expect(!monitor.isOn)
    }

    @Test func refreshPicksUpAMissedChange() {
        let fake = FakeLowPower()
        let monitor = LowPowerMonitor(read: { fake.on }, center: NotificationCenter())
        #expect(!monitor.isOn)
        fake.on = true
        monitor.refresh()
        #expect(monitor.isOn)
    }

    @Test func modelRedrawsTheLabelWhenLowPowerChanges() {
        let model = BatteryModel(history: nil)
        model.snapshot = BatteryFixtures.snapshot("charging-synth")
        final class Counter: @unchecked Sendable { var value = 0 }
        let changes = Counter()
        withObservationTracking { _ = model.labelContent } onChange: { changes.value += 1 }
        model.lowPower = true
        #expect(changes.value == 1)
        #expect(model.labelContent == LabelContent(percent: 34, glyph: .bolt, lowPower: true))
        // Setting the same value again must not redraw.
        withObservationTracking { _ = model.labelContent } onChange: { changes.value += 1 }
        model.lowPower = true
        #expect(changes.value == 1)
    }

    @Test func itemFeedsLowPowerIntoTheLabel() async throws {
        let fake = FakeLowPower()
        let center = NotificationCenter()
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .battery))
        let item = BatteryItem(ctx, historyURL: TempHistory().url, recordsHistory: false,
                               lowPower: LowPowerMonitor(read: { fake.on }, center: center))
        item.model.snapshot = BatteryFixtures.snapshot("charging-synth")
        #expect(item.model.labelContent?.lowPower == false)

        fake.on = true
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        var i = 0
        while item.model.labelContent?.lowPower != true, i < 50 {
            try await Task.sleep(for: .milliseconds(20))
            i += 1
        }
        #expect(item.model.labelContent?.lowPower == true)

        // A change the notification missed lands on the next tick.
        fake.on = false
        item.tick(now: .now)
        i = 0
        while item.model.labelContent?.lowPower != false, i < 50 {
            try await Task.sleep(for: .milliseconds(20))
            i += 1
        }
        #expect(item.model.lowPower == false)
    }
}

/// Straight (unpremultiplied) sRGB at 2x, addressed in points from the bottom left.
@MainActor
struct RGBA {
    struct Pixel: CustomStringConvertible {
        let r, g, b, a: CGFloat
        var isYellow: Bool { r > 0.85 && g > 0.65 && b < 0.3 }
        var isNeutral: Bool { abs(r - g) < 0.05 && abs(g - b) < 0.05 }
        var description: String { String(format: "(%.2f %.2f %.2f a%.2f)", r, g, b, a) }
    }

    private let rep: NSBitmapImageRep
    private let height: Int

    init(_ image: NSImage) {
        let width = Int(image.size.width * 2)
        height = Int(image.size.height * 2)
        rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: width * 4, bitsPerPixel: 32)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
    }

    func at(_ x: CGFloat, _ y: CGFloat) -> Pixel {
        let c = rep.colorAt(x: Int(x * 2), y: height - 1 - Int(y * 2))!
        let a = c.alphaComponent
        guard a > 0 else { return Pixel(r: 0, g: 0, b: 0, a: 0) }
        // colorAt hands back premultiplied components for this bitmap layout.
        return Pixel(r: c.redComponent / a, g: c.greenComponent / a, b: c.blueComponent / a, a: a)
    }
}
