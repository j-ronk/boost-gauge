import AppKit
import Testing
@testable import BoostGaugeKit

@MainActor
struct BatteryIconTests {
    @Test func fillIsProportional() {
        #expect(BatteryIcon.fillWidth(percent: 34, innerWidth: 20) == 6.8)
        #expect(BatteryIcon.fillWidth(percent: 0, innerWidth: 20) == 0)
        #expect(BatteryIcon.fillWidth(percent: 100, innerWidth: 20) == 20)
        #expect(BatteryIcon.fillWidth(percent: 1, innerWidth: 20) == 1)
        #expect(BatteryIcon.fillWidth(percent: 3, innerWidth: 20) == 1)
        #expect(BatteryIcon.fillWidth(percent: 150, innerWidth: 20) == 20)
        #expect(BatteryIcon.fillWidth(percent: -5, innerWidth: 20) == 0)
    }

    @Test func glyphs() {
        #expect(BatteryIcon.glyph(for: .charging(42)) == .bolt)
        #expect(BatteryIcon.glyph(for: .charging(nil)) == .bolt)
        #expect(BatteryIcon.glyph(for: .charged) == .plug)
        #expect(BatteryIcon.glyph(for: .onHold) == .plug)
        #expect(BatteryIcon.glyph(for: .notCharging) == .plug)
        #expect(BatteryIcon.glyph(for: .drainingOnAC) == .plug)
        #expect(BatteryIcon.glyph(for: .onBattery(10)) == .none)
    }

    @Test func templateAndConstantSize() {
        let empty = BatteryIcon.image(percent: 0, glyph: .none)
        let full = BatteryIcon.image(percent: 100, glyph: .bolt)
        let plug = BatteryIcon.image(percent: 55, glyph: .plug)
        #expect(empty.isTemplate && full.isTemplate && plug.isTemplate)
        #expect(empty.size == full.size)
        #expect(plug.size == full.size)
        #expect(empty.size.width > 0)
    }

    @Test func fillChangesPixels() throws {
        func inkedColumns(_ image: NSImage) throws -> Int {
            let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let rep = NSBitmapImageRep(cgImage: cg)
            let midY = rep.pixelsHigh / 2
            return (0..<rep.pixelsWide).filter { (rep.colorAt(x: $0, y: midY)?.alphaComponent ?? 0) > 0.9 }.count
        }
        let low = try inkedColumns(BatteryIcon.image(percent: 10, glyph: .none))
        let high = try inkedColumns(BatteryIcon.image(percent: 90, glyph: .none))
        #expect(high > low)
    }

    @Test func percentageSitsInsideTheBody() {
        let icon = BatteryIcon.label(percent: 34, glyph: .none, showPercentage: false)
        let withNumber = BatteryIcon.label(percent: 34, glyph: .none, showPercentage: true)
        #expect(icon.isTemplate && withNumber.isTemplate)
        #expect(withNumber.size == icon.size)
        #expect(icon.size == BatteryIcon.image(percent: 34, glyph: .none).size)
        #expect(Alpha(withNumber) != Alpha(icon))
    }

    /// Modern style: a solid two-tone pill, not an outlined frame. The empty part is dimmed, not clear.
    @Test func bodyIsASolidTwoTonePill() {
        let empty = Alpha(BatteryIcon.image(percent: 0, glyph: .none))
        let full = Alpha(BatteryIcon.image(percent: 100, glyph: .none))
        let half = Alpha(BatteryIcon.image(percent: 50, glyph: .none))
        let mid = BatteryIcon.bodyRect.midY
        #expect(abs(empty.at(BatteryIcon.bodyRect.midX, mid) - 0.4) < 0.05)
        #expect(full.at(BatteryIcon.bodyRect.midX, mid) > 0.95)
        #expect(half.at(BatteryIcon.bodyRect.minX + 4, mid) > 0.95)
        #expect(abs(half.at(BatteryIcon.bodyRect.maxX - 4, mid) - 0.4) < 0.05)
        // Rounded corners: the very corner of the body's box is outside the pill.
        #expect(full.at(BatteryIcon.bodyRect.minX + 0.25, BatteryIcon.bodyRect.minY + 0.25) < 0.1)
    }

    @Test func terminalLightsUpOnlyWhenFull() {
        let x = BatteryIcon.bodyRect.maxX + 1.75
        let mid = BatteryIcon.bodyRect.midY
        #expect(Alpha(BatteryIcon.image(percent: 100, glyph: .none)).at(x, mid) > 0.95)
        #expect(abs(Alpha(BatteryIcon.image(percent: 99, glyph: .none)).at(x, mid) - 0.4) < 0.05)
    }

    @Test func numberIsCutOutOfTheCharge() {
        let plain = Alpha(BatteryIcon.label(percent: 100, glyph: .none, showPercentage: false))
        let number = Alpha(BatteryIcon.label(percent: 100, glyph: .none, showPercentage: true))
        let body = BatteryIcon.bodyRect.insetBy(dx: 5, dy: 3)
        #expect(plain.minAlpha(in: body) > 0.95)
        #expect(number.minAlpha(in: body) < 0.05)
    }

    /// As in macOS 27, the digits are cut right through the body: clear over the charge and over the empty part.
    @Test func numberIsCutThroughTheWholeBody() {
        let number = Alpha(BatteryIcon.label(percent: 50, glyph: .none, showPercentage: true))
        let plain = Alpha(BatteryIcon.label(percent: 50, glyph: .none, showPercentage: false))
        let body = BatteryIcon.bodyRect
        let fillX = body.minX + body.width / 2
        let left = CGRect(x: body.minX + 3, y: body.minY + 3, width: fillX - body.minX - 3.5, height: body.height - 6)
        let right = CGRect(x: fillX + 0.5, y: body.minY + 3, width: body.maxX - fillX - 3.5, height: body.height - 6)
        #expect(number.minAlpha(in: left) < 0.05)
        #expect(number.minAlpha(in: right) < 0.05)
        // Nothing in the number is drawn solid over the dim part.
        #expect(number.maxAlpha(in: right) < 0.45)
        #expect(plain.minAlpha(in: right) > 0.35)
    }

    @Test func numberAndGlyphStayInsideThePill() {
        let b = BatteryIcon.bodyRect
        let corners = [CGPoint(x: b.minX + 0.25, y: b.minY + 0.25), CGPoint(x: b.minX + 0.25, y: b.maxY - 0.25),
                       CGPoint(x: b.maxX - 0.25, y: b.minY + 0.25), CGPoint(x: b.maxX - 0.25, y: b.maxY - 0.25)]
        for percent in [0, 8, 34, 88, 100] {
            for glyph in [BatteryGlyph.none, .bolt, .plug] {
                let a = Alpha(BatteryIcon.label(percent: percent, glyph: glyph, showPercentage: true, style: .numberAndGlyph))
                for c in corners { #expect(a.at(c.x, c.y) < 0.1, "\(percent) \(glyph) \(c)") }
                // Nothing above or below the body except the bolt's overhang, and there's no bolt beside a number.
                #expect(a.maxAlpha(in: CGRect(x: 0, y: 0, width: b.maxX, height: b.minY)) < 0.05, "\(percent) \(glyph)")
            }
        }
    }

    /// The digits' ink, not their advance width or line box, sits in the middle of the body, both ways.
    @Test(arguments: [5, 50, 93, 100])
    func digitsAreOpticallyCentred(percent: Int) throws {
        let ink = try #require(DigitInk(percent: percent))
        let body = BatteryIcon.bodyRect
        #expect(abs(ink.box.midX - body.midX) <= 0.5, "\(percent)% dx \(ink.box.midX - body.midX)")
        #expect(abs(ink.box.midY - body.midY) <= 0.5, "\(percent)% dy \(ink.box.midY - body.midY) box \(ink.box) body \(body)")
    }

    /// With the number-and-glyph style the pair sits on the body's middle. Horizontally the small glyph's image
    /// still carries the symbol's side padding, so only the vertical is pinned here.
    @Test(arguments: [8, 34, 88])
    func numberAndGlyphAreCentredVertically(percent: Int) throws {
        for glyph in [BatteryGlyph.bolt, .plug] {
            let ink = try #require(DigitInk(percent: percent, glyph: glyph))
            #expect(abs(ink.box.midY - BatteryIcon.bodyRect.midY) <= 0.5,
                    "\(percent)% \(glyph) dy \(ink.box.midY - BatteryIcon.bodyRect.midY)")
        }
    }

    /// Measured off the native macOS 27 icon at 2x: digits about 7.6 pt tall in a 12 pt body.
    @Test func digitsAreNativeSize() throws {
        let ink = try #require(DigitInk(percent: 50))
        #expect(ink.box.height >= 7.25 && ink.box.height <= 7.9, "\(ink.box.height)")
    }

    /// Native terminal: 1.5 x 3.75 pt, 1 pt off the body.
    @Test func terminalIsNativeSize() {
        let a = Alpha(BatteryIcon.image(percent: 100, glyph: .none))
        let b = BatteryIcon.bodyRect
        #expect(a.at(b.maxX + 0.25, b.midY) < 0.05)
        #expect(a.at(b.maxX + 1.25, b.midY) > 0.95)
        #expect(a.at(b.maxX + 2.75, b.midY) < 0.05)
        #expect(a.at(b.maxX + 1.25, b.midY + 1.6) > 0.5)
        #expect(a.at(b.maxX + 1.25, b.midY + 2.25) < 0.05)
    }

    @Test func boltHasAKnockoutGap() {
        let bolt = Alpha(BatteryIcon.image(percent: 100, glyph: .bolt))
        let body = BatteryIcon.bodyRect.insetBy(dx: 2, dy: 1)
        #expect(bolt.minAlpha(in: body) < 0.05)
        #expect(bolt.at(BatteryIcon.bodyRect.midX, BatteryIcon.bodyRect.midY) > 0.95)
    }

    @Test func chargingNumberStyles() {
        let both = BatteryIcon.label(percent: 34, glyph: .bolt, showPercentage: true, style: .numberAndGlyph)
        let glyph = BatteryIcon.label(percent: 34, glyph: .bolt, showPercentage: true, style: .glyphOnly)
        #expect(Alpha(both) != Alpha(glyph))
        // Glyph only shows the same big bolt as the icon without a number.
        #expect(Alpha(glyph) == Alpha(BatteryIcon.label(percent: 34, glyph: .bolt, showPercentage: false)))
        // On battery there is no glyph, so both styles show the number.
        #expect(Alpha(BatteryIcon.label(percent: 34, glyph: .none, showPercentage: true, style: .glyphOnly))
            == Alpha(BatteryIcon.label(percent: 34, glyph: .none, showPercentage: true, style: .numberAndGlyph)))
    }
}

@MainActor
struct BatteryIconCacheTests {
    @Test func sameLabelIsTheSameImage() {
        let a = BatteryIcon.label(percent: 61, glyph: .bolt, showPercentage: true)
        #expect(BatteryIcon.label(percent: 61, glyph: .bolt, showPercentage: true) === a)
        #expect(BatteryIcon.label(percent: 62, glyph: .bolt, showPercentage: true) !== a)
        #expect(BatteryIcon.label(percent: 61, glyph: .plug, showPercentage: true) !== a)
        #expect(BatteryIcon.label(percent: 61, glyph: .bolt, showPercentage: false) !== a)
        #expect(BatteryIcon.label(percent: 61, glyph: .bolt, showPercentage: true, style: .glyphOnly)
            !== BatteryIcon.label(percent: 61, glyph: .bolt, showPercentage: true, style: .numberAndGlyph))
    }
}

/// An image's alpha at 2x, addressed in points from the bottom left like AppKit drawing.
@MainActor
struct Alpha: Equatable {
    let width: Int
    let height: Int
    let values: [UInt8]

    init(_ image: NSImage) {
        width = Int(image.size.width * 2)
        height = Int(image.size.height * 2)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: width * 4, bitsPerPixel: 32)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.bitmapData!
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { out[y * width + x] = data[y * width * 4 + x * 4 + 3] }
        }
        values = out
    }

    /// Bitmap rows run top down; points run bottom up.
    func at(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let px = min(max(Int(x * 2), 0), width - 1)
        let py = min(max(height - 1 - Int(y * 2), 0), height - 1)
        return CGFloat(values[py * width + px]) / 255
    }

    func maxAlpha(in rect: CGRect) -> CGFloat {
        var highest: CGFloat = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX { highest = max(highest, at(x, y)); x += 0.5 }
            y += 0.5
        }
        return highest
    }

    func minAlpha(in rect: CGRect) -> CGFloat {
        var lowest: CGFloat = 1
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX { lowest = min(lowest, at(x, y)); x += 0.5 }
            y += 0.5
        }
        return lowest
    }
}

/// The ink box in points of the number (and glyph, if any): pixels where the label differs from the bare icon.
@MainActor
struct DigitInk {
    let box: CGRect

    init?(percent: Int, glyph: BatteryGlyph = .none) {
        let number = Alpha(BatteryIcon.label(percent: percent, glyph: glyph, showPercentage: true, style: .numberAndGlyph))
        let plain = Alpha(BatteryIcon.label(percent: percent, glyph: .none, showPercentage: false))
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for py in 0..<number.height {
            for px in 0..<number.width {
                let n = CGFloat(number.values[py * number.width + px]) / 255
                let p = CGFloat(plain.values[py * plain.width + px]) / 255
                // How far the pixel moved toward the opposite of the body, so solid and cut-out digits weigh the same.
                let reach = n > p ? 1 - p : p
                guard reach > 0.1, abs(n - p) / reach > 0.5 else { continue }
                minX = min(minX, px); maxX = max(maxX, px); minY = min(minY, py); maxY = max(maxY, py)
            }
        }
        guard minX <= maxX else { return nil }
        // Bitmap rows run top down; points run bottom up.
        box = CGRect(x: CGFloat(minX) / 2, y: CGFloat(number.height - 1 - maxY) / 2,
                     width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2)
    }
}
