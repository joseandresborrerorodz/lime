import AppKit

/// Draws shapes as pieces of glass: a translucent body, a sheen that fades
/// from the top, and a bright inner rim that catches light along the upper edge.
enum Glass {
    private static func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }

    static func drawTile(_ path: NSBezierPath, tint: NSColor?, dark: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = path.bounds

        // Body: frosted white, or tinted glass for the selection.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        (tint?.withAlphaComponent(0.5) ?? white(dark ? 0.07 : 0.2)).setFill()
        path.fill()
        // Sheen: bright at the top, gone by the middle.
        NSGradient(colors: [white(dark ? 0.16 : 0.32), white(0), white(dark ? 0.03 : 0.06)],
                   atLocations: [0, 0.55, 1], colorSpace: .sRGB)?
            .draw(in: bounds, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Rim: an inner stroke, brightest at the top edge.
        let outline = path.quartzPath
        let rim = outline.copy(strokingWithWidth: 2.4, lineCap: .round, lineJoin: .round, miterLimit: 1)
        context.saveGState()
        context.addPath(outline)
        context.clip()
        context.addPath(rim)
        context.clip()
        NSGradient(colors: [white(dark ? 0.6 : 0.95), white(dark ? 0.1 : 0.3), white(dark ? 0.22 : 0.55)],
                   atLocations: [0, 0.6, 1], colorSpace: .sRGB)?
            .draw(in: bounds, angle: -90)
        context.restoreGState()

        // A faint outer edge keeps light glass defined on light backgrounds.
        if !dark {
            NSColor(white: 0, alpha: 0.07).setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
    }
}

extension NSBezierPath {
    /// The same outline as a CGPath (`cgPath` needs macOS 14).
    var quartzPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            default: path.addQuadCurve(to: points[1], control: points[0])
            }
        }
        return path
    }
}
