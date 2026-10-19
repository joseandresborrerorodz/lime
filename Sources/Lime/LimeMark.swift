import AppKit

/// The Lime mark: eight rounded wedges around an open centre, drawn in code
/// so it stays crisp at any size (menu bar, app icon, docs).
enum LimeMark {
    static let wedgeCount = 8

    /// Outline of every wedge inside a circle of `radius` around `center`.
    static func wedges(center: NSPoint, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let step = 2 * CGFloat.pi / CGFloat(wedgeCount)
        let halfGap = 0.075 * step
        for index in 0..<wedgeCount {
            let mid = .pi / 2 - CGFloat(index) * step
            let from = mid - step / 2 + halfGap, to = mid + step / 2 - halfGap
            // Tip, then the outer edge as three points; rounding the middle one
            // with the full radius bows the edge into an arc.
            let points = [
                point(center, radius * 0.16, mid),
                point(center, radius, to),
                point(center, radius, mid),
                point(center, radius, from),
            ]
            let radii = [radius * 0.05, radius * 0.1, radius, radius * 0.1]
            appendRoundedPolygon(points, radii: radii, to: path)
        }
        return path
    }

    private static func point(_ center: NSPoint, _ radius: CGFloat, _ angle: CGFloat) -> NSPoint {
        NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    /// Closed polygon with each corner rounded by a tangent arc.
    private static func appendRoundedPolygon(_ points: [NSPoint], radii: [CGFloat], to path: NSBezierPath) {
        let count = points.count
        let last = points[count - 1], first = points[0]
        path.move(to: NSPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for index in 0..<count {
            path.appendArc(from: points[index], to: points[(index + 1) % count], radius: radii[index])
        }
        path.close()
    }

    /// Full-colour mark with a lime gradient from the centre outward.
    static func drawColor(in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let shape = wedges(center: center, radius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.88, green: 0.97, blue: 0.30, alpha: 1),
            NSColor(calibratedRed: 0.62, green: 0.90, blue: 0.10, alpha: 1),
            NSColor(calibratedRed: 0.33, green: 0.74, blue: 0.10, alpha: 1),
        ])?.draw(fromCenter: center, radius: radius * 0.1, toCenter: center, radius: radius, options: [])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Monochrome template image for the menu bar.
    static func menuBarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.setFill()
            wedges(center: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2 - 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 1024 × 1024 app icon: the mark on a white rounded square.
    static func appIconPNG() -> Data? {
        let side: CGFloat = 1024
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.shadowBlurRadius = 24
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()
        NSShadow().set()
        drawColor(in: tile.insetBy(dx: 92, dy: 92))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
