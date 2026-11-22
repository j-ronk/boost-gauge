import AppKit

enum BatteryGlyph: Hashable { case none, bolt, plug }

/// How the label is coloured.
enum BatteryTint: Hashable {
    /// The menu bar tints it for light, dark and highlight.
    case template
    /// Yellow charge, as the system shows in Low Power Mode. A template image can't carry colour, so the rest is
    /// drawn in the menu bar's label colour for the appearance the label sits on.
    case lowPower(dark: Bool)
}

/// How a charging or plugged-in glyph shares the body with the percentage.
enum BatteryNumberStyle: Hashable {
    /// Number with a small glyph after it, both inside the body.
    case numberAndGlyph
    /// The glyph replaces the number while plugged in.
    case glyphOnly
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
        // The empty part of the body and the terminal sit behind the charge, as in the system icon.
        static let dimAlpha: CGFloat = 0.4
        // The bolt overhangs the body as in the system icon; the plug is wider, so it stays inside.
        static func glyphHeight(_ glyph: BatteryGlyph) -> CGFloat { glyph == .plug ? 10 : 14 }
        static func smallGlyphHeight(_ glyph: BatteryGlyph) -> CGFloat { glyph == .plug ? 7 : 8 }
        static let knockout: CGFloat = 1
        static let numberSize: CGFloat = 10.5
        static let minNumberSize: CGFloat = 7.5
        static let numberWeight: NSFont.Weight = .medium
        static let numberGlyphSpacing: CGFloat = 1
        static let numberPadding: CGFloat = 1.5
        static var iconWidth: CGFloat { (body.width + nubGap + nub.width).rounded(.up) }
    }

    /// The lead picks between the two from the renders; this is the one the menu bar uses.
    static let numberStyle: BatteryNumberStyle = .glyphOnly

    /// Where the body sits in the label image, in points.
    static var bodyRect: CGRect {
        CGRect(origin: CGPoint(x: 0, y: ((Metrics.canvasHeight - Metrics.body.height) / 2).rounded()), size: Metrics.body)
    }

    static func fillWidth(percent: Int, innerWidth: CGFloat) -> CGFloat {
        let p = min(max(percent, 0), 100)
        guard p > 0 else { return 0 }
        return max(1, innerWidth * CGFloat(p) / 100)
    }

    static func glyph(for state: ChargeState) -> BatteryGlyph {
        switch state {
        case .charging: .bolt
        case .charged, .onHold, .notCharging, .drainingOnAC: .plug
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
        let style: BatteryNumberStyle
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
                // systemYellow is dynamic; pin it to the appearance the label sits on, not the app's.
                var yellow = NSColor.systemYellow
                NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                    yellow = NSColor.systemYellow.usingColorSpace(.sRGB) ?? .systemYellow
                }
                charge = yellow
            }
        }
    }

    @MainActor private static let labelCache = LabelImageCache<LabelKey>(limit: 16)

    /// The percentage sits inside the body, as in macOS 26, so the item is the same width either way.
    /// Same inputs give the same image instance; see `LabelImageCache` for why that matters in the menu bar.
    @MainActor static func label(percent: Int, glyph: BatteryGlyph, showPercentage: Bool,
                                 style: BatteryNumberStyle? = nil, tint: BatteryTint = .template) -> NSImage {
        let percent = min(max(percent, 0), 100)
        // Style only matters when a number and a glyph compete for the body; one key for the rest.
        let style = showPercentage && glyph != .none ? style ?? numberStyle : .numberAndGlyph
        let key = LabelKey(percent: percent, glyph: glyph, showPercentage: showPercentage, style: style, tint: tint)
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
        // The terminal never turns yellow; it goes solid at 100% either way.
        (key.percent >= 100 ? palette.ink : dim(palette.ink)).set()
        halfCapsule(nub).fill()

        if key.showPercentage && !(key.glyph != .none && key.style == .glyphOnly) {
            drawNumber(key, in: body, ctx: ctx)
        } else if let mask = glyphImage(key.glyph, height: Metrics.glyphHeight(key.glyph)) {
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

    /// Digits cut right through the body, over the charge and the empty part alike, as in macOS 27.
    private static func drawNumber(_ key: LabelKey, in body: CGRect, ctx: CGContext) {
        let full = body.width - 2 * Metrics.numberPadding
        var glyph = glyphImage(key.glyph, height: Metrics.smallGlyphHeight(key.glyph))
        var (line, ink) = fitted(key.percent, room: full - (glyph.map { $0.size.width + Metrics.numberGlyphSpacing } ?? 0))
        // A number that can't fit beside the glyph keeps the body to itself rather than spill out of it.
        if glyph != nil, ink.width > full - glyph!.size.width - Metrics.numberGlyphSpacing {
            glyph = nil
            (line, ink) = fitted(key.percent, room: full)
        }
        let glyphWidth = glyph.map { $0.size.width + Metrics.numberGlyphSpacing } ?? 0
        // Centre the digits' ink: advance widths carry side bearings and the line box carries descender space.
        let inkLeft = body.midX - (ink.width + glyphWidth) / 2
        // CoreText takes the baseline itself; NSAttributedString.draw(at:) adds line spacing we'd have to guess.
        // It also drops the baseline to a whole device pixel, so round it to the nearest one first.
        let scale = max(1, abs(ctx.convertToDeviceSpace(CGSize(width: 1, height: 1)).height))
        let pen = CGPoint(x: inkLeft - ink.minX, y: ((body.midY - ink.midY) * scale).rounded() / scale)
        let glyphRect = glyph.map {
            CGRect(x: inkLeft + ink.width + Metrics.numberGlyphSpacing, y: body.midY - $0.size.height / 2,
                   width: $0.size.width, height: $0.size.height)
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: body, xRadius: Metrics.bodyRadius, yRadius: Metrics.bodyRadius).addClip()
        ctx.setBlendMode(.destinationOut)
        ctx.textMatrix = .identity
        ctx.textPosition = pen
        CTLineDraw(line, ctx)
        if let glyph, let glyphRect {
            glyph.draw(in: glyphRect, from: .zero, operation: .destinationOut, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The largest number size whose ink fits `room`, down to the smallest that stays legible.
    /// The ink box is relative to the pen position on the baseline.
    private static func fitted(_ percent: Int, room: CGFloat) -> (CTLine, CGRect) {
        var size = Metrics.numberSize
        while true {
            let font = NSFont.systemFont(ofSize: size, weight: Metrics.numberWeight)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(percent)", attributes: [
                .font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.black.cgColor,
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
        let names: [String]
        switch glyph {
        case .none: return nil
        case .bolt: names = ["bolt.fill"]
        case .plug: names = ["powerplug.portrait.fill", "powerplug.fill"]
        }
        let config = NSImage.SymbolConfiguration(pointSize: height, weight: .bold)
        guard let symbol = names.lazy.compactMap({
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }).first else { return nil }
        let scale = height / max(symbol.size.height, 1)
        let size = CGSize(width: symbol.size.width * scale, height: height)
        return NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceIn)
            return true
        }
    }
}
