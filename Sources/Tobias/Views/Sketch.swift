import AppKit
import SwiftUI

// Building blocks of the hand-drawn look: wobbly outlines, hard offset shadows,
// sticky notes with a push pin, and Tobias the pixel cat.

/// A rectangle whose corners have different elliptical radii, like CSS `border-radius: a b c d / e f g h`.
struct SketchShape: InsettableShape {
    struct Corner { var rx: CGFloat; var ry: CGFloat }
    var topLeading: Corner
    var topTrailing: Corner
    var bottomTrailing: Corner
    var bottomLeading: Corner
    var inset: CGFloat = 0

    init(_ h: (CGFloat, CGFloat, CGFloat, CGFloat), _ v: (CGFloat, CGFloat, CGFloat, CGFloat)) {
        topLeading = Corner(rx: h.0, ry: v.0)
        topTrailing = Corner(rx: h.1, ry: v.1)
        bottomTrailing = Corner(rx: h.2, ry: v.2)
        bottomLeading = Corner(rx: h.3, ry: v.3)
    }

    init(_ r: (CGFloat, CGFloat, CGFloat, CGFloat)) { self.init(r, r) }

    static let card = SketchShape((22, 14, 24, 12), (14, 24, 12, 22))
    static let row = SketchShape((16, 10, 18, 9), (10, 18, 9, 16))
    static let button = SketchShape((16, 10, 16, 10), (10, 16, 10, 16))
    static let control = SketchShape((12, 8, 12, 8), (8, 12, 8, 12))
    static let badge = SketchShape((12, 8, 12, 8))
    static let tiny = SketchShape((9, 6, 9, 6))
    static let bar = SketchShape((6, 4, 6, 4))
    static let note = SketchShape((4, 4, 14, 4))

    func inset(by amount: CGFloat) -> SketchShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let k: CGFloat = 0.5523
        func clamp(_ c: Corner) -> Corner {
            Corner(rx: max(0, min(c.rx - inset, r.width / 2)), ry: max(0, min(c.ry - inset, r.height / 2)))
        }
        let tl = clamp(topLeading), tr = clamp(topTrailing), br = clamp(bottomTrailing), bl = clamp(bottomLeading)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl.rx, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr.rx, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + tr.ry),
                   control1: CGPoint(x: r.maxX - tr.rx * (1 - k), y: r.minY),
                   control2: CGPoint(x: r.maxX, y: r.minY + tr.ry * (1 - k)))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br.ry))
        p.addCurve(to: CGPoint(x: r.maxX - br.rx, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.maxY - br.ry * (1 - k)),
                   control2: CGPoint(x: r.maxX - br.rx * (1 - k), y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bl.rx, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - bl.ry),
                   control1: CGPoint(x: r.minX + bl.rx * (1 - k), y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.maxY - bl.ry * (1 - k)))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl.ry))
        p.addCurve(to: CGPoint(x: r.minX + tl.rx, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + tl.ry * (1 - k)),
                   control2: CGPoint(x: r.minX + tl.rx * (1 - k), y: r.minY))
        p.closeSubpath()
        return p
    }
}

extension View {
    /// Fills the view's background with a sketch shape, an ink outline and an optional hard shadow.
    func sketch(
        _ shape: SketchShape = .row,
        fill: Color = Theme.Palette.surface,
        border: Color = Theme.Palette.line,
        lineWidth: CGFloat = 1.5,
        dashed: Bool = false,
        shadow: Color? = nil,
        shadowOffset: CGSize = CGSize(width: 2, height: 2)
    ) -> some View {
        background {
            ZStack {
                if let shadow { shape.fill(shadow).offset(shadowOffset) }
                shape.fill(fill)
                shape.strokeBorder(border, style: StrokeStyle(lineWidth: lineWidth, dash: dashed ? [5, 4] : []))
            }
        }
    }
}

/// The app's buttons: an outlined paper button, a solid ink one and a red destructive one.
struct SketchButtonStyle: ButtonStyle {
    enum Kind { case secondary, primary, destructive }
    var kind: Kind = .secondary
    var height: CGFloat = 44
    var fill: Color?

    func makeBody(configuration: Configuration) -> some View {
        SketchButton(configuration: configuration, kind: kind, height: height, fill: fill)
    }

    private struct SketchButton: View {
        let configuration: Configuration
        let kind: Kind
        let height: CGFloat
        let fill: Color?
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(Theme.Typography.button)
                .foregroundStyle(foreground)
                .padding(.horizontal, 20)
                .frame(height: height)
                .contentShape(SketchShape.button)
                .sketch(.button, fill: background, border: border, lineWidth: 2,
                        shadow: pressed ? nil : Theme.Palette.shadow,
                        shadowOffset: kind == .secondary ? CGSize(width: 2, height: 3) : CGSize(width: 3, height: 4))
                .offset(x: pressed ? 1 : 0, y: pressed ? 2 : 0)
                .opacity(isEnabled ? 1 : 0.45)
        }

        private var foreground: Color {
            switch kind {
            case .secondary: return Theme.Palette.ink
            case .primary: return Theme.Palette.ground
            case .destructive: return .white
            }
        }

        private var background: Color {
            if let fill { return fill }
            switch kind {
            case .secondary: return Theme.Palette.surface
            case .primary: return Theme.Palette.ink
            case .destructive: return Theme.Palette.destructive
            }
        }

        private var border: Color {
            switch kind {
            case .secondary: return Theme.Palette.line
            case .primary: return Theme.Palette.ink
            case .destructive: return Theme.Palette.destructiveBorder
            }
        }
    }
}

/// A small outlined pill: "Downloads again", "Blocked", "Manual", "App removed".
struct SketchBadge: View {
    enum Tone { case warning, neutral }
    let text: String
    var tone: Tone = .neutral

    var body: some View {
        let color = tone == .warning ? Theme.Palette.warningText : Theme.Palette.secondaryText
        Text(text)
            .font(Theme.Typography.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 1)
            .sketch(.badge, fill: tone == .warning ? Theme.Palette.warningTint : Theme.Palette.neutralBadge, border: color)
            .fixedSize()
    }
}

struct DashedDivider: View {
    var color: Color = Theme.Palette.dash
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: lineWidth / 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: lineWidth / 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: [5, 4]))
        }
        .frame(height: lineWidth)
    }
}

/// Diagonal stripes, used for the reclaimable part of the disk bar.
struct Stripes: View {
    var stripe: Color = Theme.Palette.accent
    var gap: Color = Theme.Palette.accentStripe
    var width: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(gap))
            var x = -size.height
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(p, with: .color(stripe), lineWidth: width * 0.7)
                x += width * 2
            }
        }
    }
}

/// A sticky note held by a red push pin. When `onDismiss` is set, the pin is the dismiss button.
struct StickyNote<Content: View>: View {
    var tint: Color = Theme.Palette.note
    var onDismiss: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.leading, 30).padding(.trailing, 24).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                SketchShape.note.fill(tint)
                    .shadow(color: .black.opacity(0.08), radius: 0.5, y: 1)
                    .shadow(color: .black.opacity(0.18), radius: 7, y: 6)
            }
            .overlay(alignment: .topLeading) {
                if let onDismiss {
                    Button(action: onDismiss) { PushPin().frame(width: 22, height: 35) }
                        .buttonStyle(.plain)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .help(Strings.dismiss)
                        .accessibilityLabel(Strings.dismiss)
                        .offset(x: -14, y: -24)
                } else {
                    PushPin().frame(width: 18, height: 30).offset(x: -2, y: -16)
                }
            }
    }
}

/// The red push pin from the design, drawn from its 40 × 64 sketch.
struct PushPin: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 40, y: size.height / 64)
            let ink = GraphicsContext.Shading.color(Color(nsColor: NSColor(hex: 0x2B2B29)))
            let red = GraphicsContext.Shading.color(Color(nsColor: NSColor(hex: 0xD4483D)))
            let head = GraphicsContext.Shading.color(Color(nsColor: NSColor(hex: 0xE2675C)))
            let needle = GraphicsContext.Shading.color(Color(nsColor: NSColor(hex: 0xFBFAF7)))
            func draw(_ path: Path, fill: GraphicsContext.Shading?, width: CGFloat) {
                if let fill { context.fill(path, with: fill) }
                context.stroke(path, with: ink, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            draw(Path { p in
                p.move(to: CGPoint(x: 18.2, y: 40.5)); p.addLine(to: CGPoint(x: 19.6, y: 62.5)); p.addLine(to: CGPoint(x: 21.9, y: 40.5))
            }, fill: needle, width: 1.8)
            draw(Path { p in
                p.move(to: CGPoint(x: 4.6, y: 37.2))
                p.addCurve(to: CGPoint(x: 20.2, y: 30.2), control1: CGPoint(x: 4.4, y: 31.4), control2: CGPoint(x: 11.8, y: 30.1))
                p.addCurve(to: CGPoint(x: 35.4, y: 37.4), control1: CGPoint(x: 28.6, y: 30.3), control2: CGPoint(x: 35.6, y: 31.6))
                p.addCurve(to: CGPoint(x: 19.8, y: 41.1), control1: CGPoint(x: 35.3, y: 40.6), control2: CGPoint(x: 28, y: 41.3))
                p.addCurve(to: CGPoint(x: 4.6, y: 37.2), control1: CGPoint(x: 11.9, y: 40.9), control2: CGPoint(x: 4.7, y: 40.4))
                p.closeSubpath()
            }, fill: red, width: 2.2)
            draw(Path { p in
                p.move(to: CGPoint(x: 10.2, y: 7.4)); p.addLine(to: CGPoint(x: 12.6, y: 31.2))
                p.addCurve(to: CGPoint(x: 27.6, y: 31.1), control1: CGPoint(x: 17, y: 32.6), control2: CGPoint(x: 23.4, y: 32.6))
                p.addLine(to: CGPoint(x: 30.1, y: 7.6))
            }, fill: red, width: 2.2)
            draw(Path { p in
                p.move(to: CGPoint(x: 16.3, y: 11)); p.addLine(to: CGPoint(x: 17, y: 29.6))
                p.move(to: CGPoint(x: 23.4, y: 10.8)); p.addLine(to: CGPoint(x: 22.8, y: 29.4))
            }, fill: nil, width: 3)
            draw(Path { p in
                p.move(to: CGPoint(x: 9.1, y: 6.4))
                p.addCurve(to: CGPoint(x: 20.4, y: 2.5), control1: CGPoint(x: 9.3, y: 3.6), control2: CGPoint(x: 14.3, y: 2.4))
                p.addCurve(to: CGPoint(x: 31.1, y: 6.9), control1: CGPoint(x: 26.6, y: 2.6), control2: CGPoint(x: 31.3, y: 3.8))
                p.addCurve(to: CGPoint(x: 19.8, y: 10.5), control1: CGPoint(x: 30.9, y: 9.6), control2: CGPoint(x: 25.8, y: 10.6))
                p.addCurve(to: CGPoint(x: 9.1, y: 6.4), control1: CGPoint(x: 13.6, y: 10.4), control2: CGPoint(x: 8.9, y: 9.2))
                p.closeSubpath()
            }, fill: head, width: 2.2)
        }
        .rotationEffect(.degrees(-40))
        .shadow(color: .black.opacity(0.25), radius: 1.5, x: 2, y: 3)
        .accessibilityHidden(true)
    }
}

/// Tobias: a white cat with green eyes on a 16 × 15 pixel grid.
enum PixelCat {
    /// Runs of pixels: (x, y, width), one row high.
    typealias Run = (x: Int, y: Int, w: Int)

    static let outline: [Run] = [
        (1, 0, 1), (14, 0, 1), (1, 1, 2), (13, 1, 2), (1, 2, 1), (3, 2, 1), (12, 2, 1), (14, 2, 1),
        (1, 3, 1), (4, 3, 1), (11, 3, 1), (14, 3, 1), (1, 4, 1), (5, 4, 6), (14, 4, 1), (1, 5, 1),
        (14, 5, 1), (0, 6, 1), (15, 6, 1), (0, 7, 1), (15, 7, 1), (0, 8, 1), (15, 8, 1), (0, 9, 1),
        (15, 9, 1), (0, 10, 1), (15, 10, 1), (0, 11, 1), (6, 11, 1), (9, 11, 1), (15, 11, 1),
        (1, 12, 1), (7, 12, 2), (14, 12, 1), (2, 13, 2), (12, 13, 2), (4, 14, 8),
    ]
    static let coat: [Run] = [
        (2, 2, 1), (13, 2, 1), (2, 3, 1), (13, 3, 1), (2, 4, 1), (13, 4, 1), (2, 5, 12), (1, 6, 14),
        (1, 7, 14), (1, 8, 2), (5, 8, 6), (13, 8, 2), (1, 9, 2), (5, 9, 6), (13, 9, 2), (1, 10, 6),
        (9, 10, 6), (2, 11, 4), (7, 11, 2), (10, 11, 4), (4, 12, 3), (9, 12, 3), (6, 13, 4),
    ]
    static let shade: [Run] = [(1, 11, 1), (14, 11, 1), (2, 12, 2), (12, 12, 2), (4, 13, 2), (10, 13, 2)]
    static let pink: [Run] = [(3, 3, 1), (12, 3, 1), (3, 4, 2), (11, 4, 2), (7, 10, 2)]
    static let eyes: [Run] = [(3, 8, 1), (12, 8, 1), (3, 9, 2), (11, 9, 2)]
    static let pupils: [Run] = [(4, 8, 1), (11, 8, 1)]

    static let layers: [(color: UInt32, runs: [Run])] = [
        (0x3A3936, outline), (0xFBFAF7, coat), (0xE4E2DB, shade),
        (0xD9A9A3, pink), (0x46A367, eyes), (0x1F2A22, pupils),
    ]

    /// `thicken` grows each outline pixel right and down by that many points, for a bolder line.
    static func draw(in context: CGContext, rect: CGRect, template: Bool = false, thicken: CGFloat = 0) {
        let px = min(rect.width / 16, rect.height / 15)
        let origin = CGPoint(x: rect.midX - px * 8, y: rect.midY - px * 7.5)
        for layer in layers {
            if template && layer.color != 0x3A3936 && layer.color != 0x1F2A22 { continue }
            context.setFillColor(template ? NSColor.black.cgColor : NSColor(hex: layer.color).cgColor)
            let grow = layer.color == 0x3A3936 ? thicken : 0
            for run in layer.runs {
                // CGContext in NSImage drawing is flipped relative to the grid, so count rows from the top.
                let y = origin.y + px * CGFloat(14 - run.y)
                context.fill(CGRect(x: origin.x + px * CGFloat(run.x), y: y - grow,
                                    width: px * CGFloat(run.w) + grow, height: px + grow))
            }
        }
    }

    /// Outline and pupils only, for the menu bar, where macOS tints it to match.
    /// The image is 4 points wider than the cat, which puts a gap before the free space text.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Half a point thicker outline: one extra pixel on Retina, so it stays crisp.
            draw(in: ctx, rect: CGRect(x: 0, y: 0.5, width: 16, height: 15), template: true, thicken: 0.5)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The app icon: Tobias on a warm grey rounded square.
    static func appIcon() -> NSImage {
        NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let tile = rect.insetBy(dx: 100, dy: 100)
            let path = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(NSColor(hex: 0xE9E7E1).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor(hex: 0xD9D7D0).cgColor)
            ctx.setLineWidth(4)
            ctx.strokePath()
            draw(in: ctx, rect: tile.insetBy(dx: 130, dy: 130))
            return true
        }
    }

    /// Writes the app icon as a 1024 × 1024 pixel PNG, the source for AppIcon.icns.
    static func writeAppIconPNG(to url: URL) -> Bool {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return false }
        rep.size = NSSize(width: 1024, height: 1024)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appIcon().draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }
}

struct PixelCatView: View {
    var body: some View {
        Canvas { context, size in
            context.withCGContext { ctx in
                // Canvas is top-left origin; flip so PixelCat.draw's bottom-left math holds.
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
                PixelCat.draw(in: ctx, rect: CGRect(origin: .zero, size: size))
            }
        }
        .aspectRatio(16 / 15, contentMode: .fit)
        .accessibilityLabel("Tobias, a white pixel cat with green eyes")
    }
}
