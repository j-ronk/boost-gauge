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

    /// macOS 27 shows the bolt whenever the Mac is on power, charging or not: the native item reads "100" and a bolt
    /// when charged on AC. On battery there is no glyph. Low Power only changes the tint (see LowPowerTests).
    @Test(arguments: [
        (ChargeState.charging(42), BatteryGlyph.bolt), (.charging(nil), .bolt), (.charged, .bolt), (.onHold, .bolt),
        (.notCharging, .bolt), (.drainingOnAC, .bolt), (.onBattery(10), .none), (.onBattery(nil), .none),
    ])
    func glyphFollowsThePowerSource(state: ChargeState, glyph: BatteryGlyph) {
        #expect(BatteryIcon.glyph(for: state) == glyph)
    }

    @Test func templateAndConstantSize() {
        let empty = BatteryIcon.image(percent: 0, glyph: .none)
        let full = BatteryIcon.image(percent: 100, glyph: .bolt)
        let charging = BatteryIcon.label(percent: 55, glyph: .bolt, showPercentage: true)
        #expect(empty.isTemplate && full.isTemplate && charging.isTemplate)
        #expect(empty.size == full.size)
        #expect(charging.size == full.size)
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

    /// The native terminal is half ink at every level, full included (0.48-0.50 of the body in a 2x capture).
    @Test(arguments: [0, 54, 99, 100])
    func terminalIsHalfInk(percent: Int) {
        let x = BatteryIcon.bodyRect.maxX + 1.6
        let a = Alpha(BatteryIcon.image(percent: percent, glyph: .none)).at(x, BatteryIcon.bodyRect.midY)
        #expect(abs(a - 0.5) < 0.03, "\(percent)% terminal \(a)")
    }

    /// The native digits aren't fully clear: about 12% of the body's ink stays in them, in light and dark alike.
    @Test func numberIsCutOutOfTheCharge() {
        let plain = Alpha(BatteryIcon.label(percent: 100, glyph: .none, showPercentage: false))
        let number = Alpha(BatteryIcon.label(percent: 100, glyph: .none, showPercentage: true))
        let body = BatteryIcon.bodyRect.insetBy(dx: 5, dy: 3)
        #expect(plain.minAlpha(in: body) > 0.95)
        #expect(abs(number.minAlpha(in: body) - 0.12) < 0.03, "\(number.minAlpha(in: body))")
    }

    /// As in macOS 27, the digits are cut right through the body: clear over the charge and over the empty part.
    @Test func numberIsCutThroughTheWholeBody() {
        let number = Alpha(BatteryIcon.label(percent: 50, glyph: .none, showPercentage: true))
        let plain = Alpha(BatteryIcon.label(percent: 50, glyph: .none, showPercentage: false))
        let body = BatteryIcon.bodyRect
        let fillX = body.minX + body.width / 2
        let left = CGRect(x: body.minX + 3, y: body.minY + 3, width: fillX - body.minX - 3.5, height: body.height - 6)
        let right = CGRect(x: fillX + 0.5, y: body.minY + 3, width: body.maxX - fillX - 3.5, height: body.height - 6)
        #expect(number.minAlpha(in: left) < 0.15)
        #expect(number.minAlpha(in: right) < 0.07)
        // Nothing in the number is drawn solid over the dim part.
        #expect(number.maxAlpha(in: right) < 0.45)
        #expect(plain.minAlpha(in: right) > 0.35)
    }

    @Test func numberAndGlyphStayInsideThePill() {
        let b = BatteryIcon.bodyRect
        let corners = [CGPoint(x: b.minX + 0.25, y: b.minY + 0.25), CGPoint(x: b.minX + 0.25, y: b.maxY - 0.25),
                       CGPoint(x: b.maxX - 0.25, y: b.minY + 0.25), CGPoint(x: b.maxX - 0.25, y: b.maxY - 0.25)]
        for percent in [0, 8, 34, 88, 100] {
            for glyph in [BatteryGlyph.none, .bolt] {
                let a = Alpha(BatteryIcon.label(percent: percent, glyph: glyph, showPercentage: true))
                for c in corners { #expect(a.at(c.x, c.y) < 0.1, "\(percent) \(glyph) \(c)") }
                // Nothing below the body: the small bolt beside a number stays inside it, unlike the big one.
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

    @Test(arguments: [8, 34, 88])
    func numberAndBoltAreCentredVertically(percent: Int) throws {
        let ink = try #require(DigitInk(percent: percent, glyph: .bolt))
        #expect(abs(ink.box.midY - BatteryIcon.bodyRect.midY) <= 0.5, "\(percent)% dy \(ink.box.midY - BatteryIcon.bodyRect.midY)")
    }

    /// Fitted to the native "100" and bolt (AC, charged) in a 2x capture: digits 6.65 pt tall and 14.5 pt wide,
    /// 0.25 pt below the middle; bolt 4.4 x 6 pt, 1 pt in from the body's end and 1 pt after the digits.
    @Test func numberAndBoltMatchNative() throws {
        let parts = try #require(InkParts(percent: 100, glyph: .bolt))
        let body = BatteryIcon.bodyRect
        #expect(abs(parts.digits.height - 6.65) <= 0.3, "digits h \(parts.digits.height)")
        #expect(abs(parts.digits.width - 14.5) <= 0.4, "digits w \(parts.digits.width)")
        #expect(abs(parts.digits.minX - body.minX - 2.06) <= 0.3, "digits left pad \(parts.digits.minX - body.minX)")
        #expect(abs(parts.digits.midY - (body.midY - 0.25)) <= 0.3, "digits dy \(parts.digits.midY - body.midY)")
        // The bolt's tips and corners are points, which barely cut their pixels, so its box reads about 0.4 pt short.
        #expect(abs(parts.glyph.height - 5.6) <= 0.3, "bolt h \(parts.glyph.height)")
        #expect(abs(parts.glyph.width - 4.05) <= 0.3, "bolt w \(parts.glyph.width)")
        #expect(abs(body.maxX - parts.glyph.maxX - 1) <= 0.3, "bolt inset \(body.maxX - parts.glyph.maxX)")
        #expect(abs(parts.glyph.minX - parts.digits.maxX - 1) <= 0.3, "gap \(parts.glyph.minX - parts.digits.maxX)")
        #expect(abs(parts.glyph.midY - body.midY) <= 0.25, "bolt dy \(parts.glyph.midY - body.midY)")
    }

    /// No percentage shrinks beside the bolt or crosses into it: "100" is the widest and still fits.
    @Test func everyNumberFitsBesideTheBolt() throws {
        let body = BatteryIcon.bodyRect
        for percent in 0...100 {
            let parts = try #require(InkParts(percent: percent, glyph: .bolt), "\(percent)%")
            #expect(parts.digits.minX >= body.minX + 1.5 - 0.3, "\(percent)% \(parts.digits)")
            #expect(parts.digits.maxX <= parts.glyph.minX - 1 + 0.3, "\(percent)% \(parts.digits) bolt \(parts.glyph)")
            #expect(abs(parts.digits.height - 6.65) <= 0.35, "\(percent)% shrank: \(parts.digits.height)")
        }
    }

    /// A short number sits in the middle of the room the bolt leaves, not against the bolt.
    @Test(arguments: [5, 54])
    func shortNumberIsCentredBesideTheBolt(percent: Int) throws {
        let parts = try #require(InkParts(percent: percent, glyph: .bolt))
        let room = (left: BatteryIcon.bodyRect.minX + 2, right: parts.glyph.minX - 1)
        #expect(abs(parts.digits.midX - (room.left + room.right) / 2) <= 0.3, "\(percent)% \(parts.digits) room \(room)")
    }

    /// Measured off the native macOS 27 icon at 2x: digits about 7.6 pt tall in a 12 pt body.
    @Test func digitsAreNativeSize() throws {
        let ink = try #require(DigitInk(percent: 50))
        #expect(ink.box.height >= 7.25 && ink.box.height <= 7.9, "\(ink.box.height)")
    }

    /// Native terminal: 1.5 x 3.75 pt, 1 pt off the body, at half ink.
    @Test func terminalIsNativeSize() {
        let a = Alpha(BatteryIcon.image(percent: 100, glyph: .none))
        let b = BatteryIcon.bodyRect
        #expect(a.at(b.maxX + 0.25, b.midY) < 0.05)
        #expect(a.at(b.maxX + 1.25, b.midY) > 0.45)
        #expect(a.at(b.maxX + 2.75, b.midY) < 0.05)
        #expect(a.at(b.maxX + 1.25, b.midY + 1.6) > 0.25)
        #expect(a.at(b.maxX + 1.25, b.midY + 2.25) < 0.05)
    }

    @Test func boltHasAKnockoutGap() {
        let bolt = Alpha(BatteryIcon.image(percent: 100, glyph: .bolt))
        let body = BatteryIcon.bodyRect.insetBy(dx: 2, dy: 1)
        #expect(bolt.minAlpha(in: body) < 0.05)
        #expect(bolt.at(BatteryIcon.bodyRect.midX, BatteryIcon.bodyRect.midY) > 0.95)
    }

    /// On power the number stays and a small bolt joins it, as the native item shows "100" and a bolt.
    @Test func onPowerShowsTheNumberAndTheBolt() throws {
        let both = Alpha(BatteryIcon.label(percent: 100, glyph: .bolt, showPercentage: true))
        let differsFromBigBolt = both != Alpha(BatteryIcon.label(percent: 100, glyph: .bolt, showPercentage: false))
        let differsFromNumberAlone = both != Alpha(BatteryIcon.label(percent: 100, glyph: .none, showPercentage: true))
        #expect(differsFromBigBolt && differsFromNumberAlone)
        let parts = try #require(InkParts(percent: 100, glyph: .bolt))
        #expect(parts.runs == 4, "1, 0, 0 and the bolt: \(parts.runs)")
    }
}

@MainActor
struct BatteryIconCacheTests {
    @Test func sameLabelIsTheSameImage() {
        let a = BatteryIcon.label(percent: 61, glyph: .bolt, showPercentage: true)
        #expect(BatteryIcon.label(percent: 61, glyph: .bolt, showPercentage: true) === a)
        #expect(BatteryIcon.label(percent: 62, glyph: .bolt, showPercentage: true) !== a)
        #expect(BatteryIcon.label(percent: 61, glyph: .none, showPercentage: true) !== a)
        #expect(BatteryIcon.label(percent: 61, glyph: .bolt, showPercentage: false) !== a)
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
        let number = Alpha(BatteryIcon.label(percent: percent, glyph: glyph, showPercentage: true))
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

/// The number's and the glyph's ink boxes in points, split at the clear columns between the characters. Edges are
/// placed within their pixel by how much of it is cut, so the boxes compare with ink measured off a capture.
@MainActor
struct InkParts {
    let digits: CGRect
    let glyph: CGRect
    let runs: Int

    init?(percent: Int, glyph: BatteryGlyph) {
        let number = Alpha(BatteryIcon.label(percent: percent, glyph: glyph, showPercentage: true))
        let plain = Alpha(BatteryIcon.label(percent: percent, glyph: .none, showPercentage: false))
        // Only inside the body: the cut-outs are what changed there.
        let body = BatteryIcon.bodyRect.insetBy(dx: 1, dy: 0.5)
        // How much of the pixel is cut, 0...1: a full cut keeps 12% of the ink (BatteryIcon's cutOut, 0.88).
        func cut(_ px: Int, _ py: Int) -> CGFloat {
            let i = py * number.width + px
            let p = CGFloat(plain.values[i])
            return p < 40 ? 0 : min(1, max(0, (p - CGFloat(number.values[i])) / (p * 0.88)))
        }
        func changed(_ px: Int, _ py: Int) -> Bool { cut(px, py) > 0.1 }
        let rows = (number.height - Int(body.maxY * 2))..<(number.height - Int(body.minY * 2))
        let cols = Int(body.minX * 2)..<Int(body.maxX * 2)
        var runs: [(Int, Int)] = []
        var start: Int?
        for px in cols {
            let inked = rows.contains { changed(px, $0) }
            if inked, start == nil { start = px }
            if !inked, let s = start { runs.append((s, px - 1)); start = nil }
        }
        if let s = start { runs.append((s, cols.upperBound - 1)) }
        guard runs.count >= 2 else { return nil }
        func box(_ c0: Int, _ c1: Int) -> CGRect {
            var minY = Int.max, maxY = Int.min
            for px in c0...c1 { for py in rows where changed(px, py) { minY = min(minY, py); maxY = max(maxY, py) } }
            func column(_ px: Int) -> CGFloat { (minY...maxY).map { cut(px, $0) }.max() ?? 0 }
            func row(_ py: Int) -> CGFloat { (c0...c1).map { cut($0, py) }.max() ?? 0 }
            let left = CGFloat(c0) + 1 - column(c0), right = CGFloat(c1) + column(c1)
            // Bitmap rows run top down; points run bottom up.
            let top = CGFloat(minY) + 1 - row(minY), bottom = CGFloat(maxY) + row(maxY)
            return CGRect(x: left / 2, y: (CGFloat(number.height) - bottom) / 2, width: (right - left) / 2, height: (bottom - top) / 2)
        }
        self.runs = runs.count
        digits = box(runs.first!.0, runs[runs.count - 2].1)
        self.glyph = box(runs.last!.0, runs.last!.1)
    }
}
