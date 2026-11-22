import AppKit

enum BatteryGlyph: Hashable { case none, bolt }

/// How the label is coloured.
enum BatteryTint: Hashable {
    /// The menu bar tints it for light, dark and highlight.
    case template
    /// Yellow charge, as the system shows in Low Power Mode. A template image can't carry colour, so the rest is
    /// drawn in the menu bar's label colour for the appearance the label sits on.
    case lowPower(dark: Bool)
    /// Red charge, as the system shows at a low level on battery. Drawn like `lowPower`, in red.
    case lowBattery(dark: Bool)
}

/// The macOS 26 menu bar battery, drawn by hand so the fill tracks the exact percent
/// (SF Symbols only step 0/25/50/75/100). Template image, except in Low Power Mode (see `BatteryTint`).
enum BatteryIcon {
    private enum Metrics {
        static let canvasHeight: CGFloat = 22
        static let body = CGSize(width: 23, height: 12)
        // Body, corner, terminal and number sizes are fitted to the native macOS 27 icon captured at 2x.
        static let bodyRadius: CGFloat = 4
        static let nubGap: CGFloat = 1
        static let nub = CGSize(width: 1.5, height: 3.75)
        // The empty part of the body sits behind the charge, as in the system icon.
        static let dimAlpha: CGFloat = 0.4
        // The native terminal is half ink at every level, full included.
        static let nubAlpha: CGFloat = 0.5
        // Without a number the bolt overhangs the body, as in the system icon.
        static let glyphHeight: CGFloat = 14
        static let knockout: CGFloat = 1
        // The native cut-outs keep 12% of the body's ink, in light and dark alike.
        static let cutOut: CGFloat = 0.88
        static let numberSize: CGFloat = 10.5
        static let minNumberSize: CGFloat = 7.5
        static let numberWeight: NSFont.Weight = .medium
        static let numberPadding: CGFloat = 1.5
        // Beside the bolt the native digits are smaller, regular weight and slightly tight, sitting 0.25 pt low.
        static let numberWithGlyphSize: CGFloat = 9
        static let numberWithGlyphWeight: NSFont.Weight = .regular
        static let numberWithGlyphKern: CGFloat = -0.1
        static let numberWithGlyphDrop: CGFloat = 0.25
        static let numberWithGlyphInset: CGFloat = 2
        // The native bolt's ink is wider than bolt.fill's own proportions.
        static let smallGlyph = CGSize(width: 4.4, height: 6)
        static let smallGlyphInset: CGFloat = 1
        static let smallGlyphGap: CGFloat = 1
        static var iconWidth: CGFloat { (body.width + nubGap + nub.width).rounded(.up) }
    }

    /// The native icon turns red with the low-battery warning; Apple doesn't document the level, so this is
    /// an observed ~10%. Confirm against the native icon.
    static let lowBatteryPercent = 10

    /// Low Power yellow wins over red; red only on battery (`glyph` is `.none` exactly when unplugged).
    static func tint(percent: Int, glyph: BatteryGlyph, lowPower: Bool, dark: Bool) -> BatteryTint {
        if lowPower { return .lowPower(dark: dark) }
        if glyph == .none, percent <= lowBatteryPercent { return .lowBattery(dark: dark) }
        return .template
    }

    /// Where the body sits in the label image, in points.
    static var bodyRect: CGRect {
        CGRect(origin: CGPoint(x: 0, y: ((Metrics.canvasHeight - Metrics.body.height) / 2).rounded()), size: Metrics.body)
    }

    static func fillWidth(percent: Int, innerWidth: CGFloat) -> CGFloat {
        let p = min(max(percent, 0), 100)
        guard p > 0 else { return 0 }
        return max(1, innerWidth * CGFloat(p) / 100)
    }

    /// macOS 27 shows the bolt whenever the Mac is on power, charging or not ("100" and a bolt when charged on AC).
    static func glyph(for state: ChargeState) -> BatteryGlyph {
        switch state {
        case .charging, .charged, .onHold, .notCharging, .drainingOnAC: .bolt
        case .onBattery: .none
        }
    }

    @MainActor static func image(percent: Int, glyph: BatteryGlyph) -> NSImage {
        label(percent: percent, glyph: glyph, showPercentage: false)
    }

    private struct LabelKey: Hashable {
        let percent: Int
        let glyph: BatteryGlyph
        let showPercentage: Bool
        let tint: BatteryTint
    }

    /// The menu bar's label colour, measured off a capture of the macOS 27 menu bar: template images there show
    /// as white at 90% over a dark wallpaper. The light side is `labelColor`'s black at 85%.
    private static func labelColor(dark: Bool) -> NSColor {
        dark ? NSColor(white: 1, alpha: 0.9) : NSColor(white: 0, alpha: 0.85)
    }

    private struct Palette {
        let charge: NSColor
        let ink: NSColor

        init(_ tint: BatteryTint) {
            switch tint {
            case .template:
                charge = .black
                ink = .black
            case .lowPower(let dark):
                ink = labelColor(dark: dark)
                charge = Self.pinned(.systemYellow, dark: dark)
            case .lowBattery(let dark):
                ink = labelColor(dark: dark)
                charge = Self.pinned(.systemRed, dark: dark)
            }
        }

        /// System colours are dynamic; pin one to the appearance the label sits on, not the app's.
        private static func pinned(_ color: NSColor, dark: Bool) -> NSColor {
            var resolved = color
            NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.sRGB) ?? color
            }
            return resolved
        }
    }

    @MainActor private static let labelCache = LabelImageCache<LabelKey>(limit: 16)

    /// The percentage sits inside the body, as in macOS 26, so the item is the same width either way.
    /// Same inputs give the same image instance; see `LabelImageCache` for why that matters in the menu bar.
    @MainActor static func label(percent: Int, glyph: BatteryGlyph, showPercentage: Bool,
                                 tint: BatteryTint = .template) -> NSImage {
        let percent = min(max(percent, 0), 100)
        let key = LabelKey(percent: percent, glyph: glyph, showPercentage: showPercentage, tint: tint)
        return labelCache.image(for: key) { draw(key) }
    }

    @MainActor private static func draw(_ key: LabelKey) -> NSImage {
        let size = CGSize(width: Metrics.iconWidth, height: Metrics.canvasHeight)
        let image = NSImage(size: size, flipped: false) { _ in
            drawBattery(key)
            return true
        }
        image.isTemplate = key.tint == .template
        return image
    }

    private static func drawBattery(_ key: LabelKey) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let palette = Palette(key.tint)
        let body = bodyRect
        let pill = NSBezierPath(roundedRect: body, xRadius: Metrics.bodyRadius, yRadius: Metrics.bodyRadius)
        // On the 2x pixel grid, so the charge and the empty part meet without an anti-aliased seam.
        let fillX = body.minX + (fillWidth(percent: key.percent, innerWidth: body.width) * 2).rounded() / 2

        // Transparency layer so knockouts clear the battery but nothing outside it.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        NSGraphicsContext.saveGraphicsState()
        pill.addClip()
        dim(palette.ink).set()
        CGRect(x: fillX, y: body.minY, width: body.maxX - fillX, height: body.height).fill()
        palette.charge.set()
        CGRect(x: body.minX, y: body.minY, width: fillX - body.minX, height: body.height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let nub = CGRect(x: body.maxX + Metrics.nubGap, y: body.midY - Metrics.nub.height / 2,
                         width: Metrics.nub.width, height: Metrics.nub.height)
        // The terminal never turns yellow.
        palette.ink.withAlphaComponent(palette.ink.alphaComponent * Metrics.nubAlpha).set()
        halfCapsule(nub).fill()

        if key.showPercentage {
            drawNumber(key, in: body, ctx: ctx)
        } else if let mask = glyphImage(key.glyph, height: Metrics.glyphHeight) {
            let rect = CGRect(x: body.midX - mask.size.width / 2, y: body.midY - mask.size.height / 2,
                              width: mask.size.width, height: mask.size.height)
            // The knockout needs the opaque mask; the label colour can be translucent.
            knockout(mask, in: rect)
            let symbol = key.tint == .template ? mask : glyphImage(key.glyph, height: rect.height, color: palette.ink) ?? mask
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        ctx.endTransparencyLayer()
    }

    private static func dim(_ color: NSColor) -> NSColor {
        color.withAlphaComponent(color.alphaComponent * Metrics.dimAlpha)
    }

    /// Digits cut right through the body, over the charge and the empty part alike, as in macOS 27. On power a small
    /// bolt sits 1 pt in from the body's end and the digits are centred in the room left of it.
    private static func drawNumber(_ key: LabelKey, in body: CGRect, ctx: CGContext) {
        let bolt = key.glyph == .bolt ? smallBolt : nil
        let glyphRect = bolt.map { _ in
            CGRect(x: body.maxX - Metrics.smallGlyphInset - Metrics.smallGlyph.width,
                   y: body.midY - Metrics.smallGlyph.height / 2, width: Metrics.smallGlyph.width, height: Metrics.smallGlyph.height)
        }
        let left = body.minX + (glyphRect == nil ? Metrics.numberPadding : Metrics.numberWithGlyphInset)
        let right = glyphRect.map { $0.minX - Metrics.smallGlyphGap } ?? body.maxX - Metrics.numberPadding
        // "100" fills the room beside the bolt, so let it reach into the usual padding before it shrinks.
        let slack = glyphRect == nil ? 0 : Metrics.numberWithGlyphInset - Metrics.numberPadding
        let (line, ink) = fitted(key.percent, room: right - left + slack, besideGlyph: glyphRect != nil)
        // Centre the digits' ink: advance widths carry side bearings and the line box carries descender space.
        let inkLeft = (left + right - ink.width) / 2
        let inkMidY = body.midY - (glyphRect == nil ? 0 : Metrics.numberWithGlyphDrop)
        // CoreText takes the baseline itself; NSAttributedString.draw(at:) adds line spacing we'd have to guess.
        // It also drops the baseline to a whole device pixel, so round it to the nearest one first.
        let scale = max(1, abs(ctx.convertToDeviceSpace(CGSize(width: 1, height: 1)).height))
        let pen = CGPoint(x: inkLeft - ink.minX, y: ((inkMidY - ink.midY) * scale).rounded() / scale)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: body, xRadius: Metrics.bodyRadius, yRadius: Metrics.bodyRadius).addClip()
        ctx.setBlendMode(.destinationOut)
        ctx.setAlpha(Metrics.cutOut)
        // The fitted tracking is a tenth of a point; whole-pixel glyph positions would swamp it.
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsFontSubpixelQuantization(false)
        ctx.setShouldSubpixelQuantizeFonts(false)
        ctx.textMatrix = .identity
        ctx.textPosition = pen
        CTLineDraw(line, ctx)
        if let bolt, let glyphRect {
            bolt.draw(in: glyphRect, from: .zero, operation: .destinationOut, fraction: Metrics.cutOut)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The largest number size whose ink fits `room`, down to the smallest that stays legible.
    /// The ink box is relative to the pen position on the baseline.
    private static func fitted(_ percent: Int, room: CGFloat, besideGlyph: Bool) -> (CTLine, CGRect) {
        var size = besideGlyph ? Metrics.numberWithGlyphSize : Metrics.numberSize
        while true {
            let font = NSFont.systemFont(ofSize: size, weight: besideGlyph ? Metrics.numberWithGlyphWeight : Metrics.numberWeight)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(percent)", attributes: [
                .font: font, .kern: besideGlyph ? Metrics.numberWithGlyphKern : 0,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.black.cgColor,
            ]))
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            if ink.width <= room || size <= Metrics.minNumberSize { return (line, ink) }
            size -= 0.5
        }
    }

    /// A clear gap around the glyph keeps it legible over both the charge and the empty part.
    private static func knockout(_ symbol: NSImage, in rect: CGRect) {
        for step in 0..<16 {
            let angle = CGFloat(step) * .pi / 8
            let offset = CGPoint(x: cos(angle) * Metrics.knockout, y: sin(angle) * Metrics.knockout)
            symbol.draw(in: rect.offsetBy(dx: offset.x, dy: offset.y), from: .zero, operation: .destinationOut, fraction: 1)
        }
    }

    private static func halfCapsule(_ rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        let r = min(rect.width, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.appendArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: 270, endAngle: 0)
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.appendArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 0, endAngle: 90)
        path.line(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.close()
        return path
    }

    /// The glyph as a solid colour at its final size, so drawing and knockouts use the same pixels.
    private static func glyphImage(_ glyph: BatteryGlyph, height: CGFloat, color: NSColor = .black) -> NSImage? {
        guard glyph == .bolt else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: height, weight: .bold)
        guard let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let scale = height / max(symbol.size.height, 1)
        let size = CGSize(width: symbol.size.width * scale, height: height)
        return NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceIn)
            return true
        }
    }

    /// The bolt beside the number, trimmed to its ink: the symbol's image carries side padding, and the native bolt is
    /// placed and sized by its ink. Drawn large once and scaled, so the trim is exact.
    private static let smallBolt: NSImage? = {
        guard let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 64, weight: .black)) else { return nil }
        let width = Int(symbol.size.width.rounded(.up)) + 2, height = Int(symbol.size.height.rounded(.up)) + 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: width * 4, bitsPerPixel: 32), let data = rep.bitmapData else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        symbol.draw(in: CGRect(x: 1, y: 1, width: symbol.size.width, height: symbol.size.height))
        NSGraphicsContext.restoreGraphicsState()
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[y * width * 4 + x * 4 + 3] > 127 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, let ink = rep.cgImage?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1,
                                                                         height: maxY - minY + 1)) else { return nil }
        return NSImage(cgImage: ink, size: Metrics.smallGlyph)
    }()
}
