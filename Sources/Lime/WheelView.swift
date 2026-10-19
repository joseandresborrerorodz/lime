import AppKit
import LimeCore

struct WheelItem {
    enum Kind {
        case operation(LimeCore.Operation)
        case action(FileAction)
    }

    let title: String
    let symbol: String
    let kind: Kind

    init(_ operation: LimeCore.Operation) {
        title = operation.title
        symbol = operation.symbol
        kind = .operation(operation)
    }

    init(_ action: FileAction) {
        title = action.title
        symbol = action.symbol
        kind = .action(action)
    }
}

/// Colours resolve against the view's appearance, so the wheel follows light and dark mode.
enum Palette {
    static let accent = NSColor(calibratedRed: 0.60, green: 0.86, blue: 0.16, alpha: 1)
    static let accentDeep = NSColor(calibratedRed: 0.42, green: 0.76, blue: 0.10, alpha: 1)
    static var segment: NSColor { .labelColor.withAlphaComponent(0.07) }
    static var segmentEdge: NSColor { .labelColor.withAlphaComponent(0.06) }
    static var hairline: NSColor { .labelColor.withAlphaComponent(0.14) }
}

/// Geometry for a ring of slices with rounded corners and constant-width gaps.
enum RingGeometry {
    /// One annular slice between boundary angles `start` < `end` (radians,
    /// counterclockwise), with every corner rounded by `corner`.
    static func slice(center: CGPoint, inner: CGFloat, outer: CGFloat,
                      start: CGFloat, end: CGFloat, gap: CGFloat, corner: CGFloat) -> NSBezierPath {
        let half = gap / 2
        let d = half + corner
        func dir(_ a: CGFloat) -> CGPoint { CGPoint(x: cos(a), y: sin(a)) }
        func add(_ p: CGPoint, _ q: CGPoint, _ k: CGFloat = 1) -> CGPoint { CGPoint(x: p.x + q.x * k, y: p.y + q.y * k) }
        func angle(_ p: CGPoint, from c: CGPoint) -> CGFloat { atan2(p.y - c.y, p.x - c.x) * 180 / .pi }

        // Inward normals of the two straight edges.
        let n1 = CGPoint(x: -sin(start), y: cos(start))
        let n2 = CGPoint(x: sin(end), y: -cos(end))
        let u1 = dir(start), u2 = dir(end)

        /// Corner circle centre plus its tangent points on the edge and on the arc.
        func roundCorner(ray u: CGPoint, normal n: CGPoint, arcRadius: CGFloat, outward: Bool)
            -> (center: CGPoint, onEdge: CGPoint, onArc: CGPoint) {
            let centerRadius = outward ? arcRadius - corner : arcRadius + corner
            let along = sqrt(max(centerRadius * centerRadius - d * d, 0))
            let c = add(add(center, u, along), n, d)
            let onEdge = add(add(center, u, along), n, half)
            let scale = arcRadius / centerRadius
            let onArc = CGPoint(x: center.x + (c.x - center.x) * scale, y: center.y + (c.y - center.y) * scale)
            return (c, onEdge, onArc)
        }

        let o1 = roundCorner(ray: u1, normal: n1, arcRadius: outer, outward: true)
        let o2 = roundCorner(ray: u2, normal: n2, arcRadius: outer, outward: true)
        let i1 = roundCorner(ray: u1, normal: n1, arcRadius: inner, outward: false)
        let i2 = roundCorner(ray: u2, normal: n2, arcRadius: inner, outward: false)

        let path = NSBezierPath()
        path.move(to: i1.onEdge)
        path.line(to: o1.onEdge)
        path.appendArc(withCenter: o1.center, radius: corner,
                       startAngle: angle(o1.onEdge, from: o1.center), endAngle: angle(o1.onArc, from: o1.center), clockwise: false)
        path.appendArc(withCenter: center, radius: outer,
                       startAngle: angle(o1.onArc, from: center), endAngle: angle(o2.onArc, from: center), clockwise: false)
        path.appendArc(withCenter: o2.center, radius: corner,
                       startAngle: angle(o2.onArc, from: o2.center), endAngle: angle(o2.onEdge, from: o2.center), clockwise: false)
        path.line(to: i2.onEdge)
        path.appendArc(withCenter: i2.center, radius: corner,
                       startAngle: angle(i2.onEdge, from: i2.center), endAngle: angle(i2.onArc, from: i2.center), clockwise: false)
        path.appendArc(withCenter: center, radius: inner,
                       startAngle: angle(i2.onArc, from: center), endAngle: angle(i1.onArc, from: center), clockwise: true)
        path.appendArc(withCenter: i1.center, radius: corner,
                       startAngle: angle(i1.onArc, from: i1.center), endAngle: angle(i1.onEdge, from: i1.center), clockwise: false)
        path.close()
        return path
    }
}

/// A ring of drop targets. Segments start at 12 o'clock and run clockwise;
/// the hub in the middle is a cancel zone.
final class WheelView: NSView {
    static let outerRadius: CGFloat = 146
    static let innerRadius: CGFloat = 62
    static let gap: CGFloat = 5
    static let cornerRadius: CGFloat = 12

    var items: [WheelItem] = [] {
        didSet { highlighted = nil; needsDisplay = true }
    }
    var mode: WheelMode = .convert { didSet { needsDisplay = true } }
    var fileCount = 1 { didSet { needsDisplay = true } }

    var onDrop: ((WheelItem) -> Void)?
    var onHighlight: (() -> Void)?

    var highlighted: Int? {
        didSet {
            guard highlighted != oldValue else { return }
            if highlighted != nil { onHighlight?() }
            needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }
    private var step: CGFloat { 360 / CGFloat(max(items.count, 1)) }

    /// Angle (degrees, counterclockwise from 3 o'clock) at the middle of a segment.
    private func midAngle(_ index: Int) -> CGFloat { 90 - CGFloat(index) * step }

    func index(at point: NSPoint) -> Int? {
        guard !items.isEmpty else { return nil }
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= Self.innerRadius, distance <= Self.outerRadius + 40 else { return nil }
        let angle = atan2(dy, dx) * 180 / .pi
        var offset = (90 - angle) / step
        offset = offset.truncatingRemainder(dividingBy: CGFloat(items.count))
        if offset < 0 { offset += CGFloat(items.count) }
        return Int(offset.rounded()) % items.count
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for index in items.indices {
            drawSegment(index)
        }
        drawHub()
    }

    private func segmentPath(_ index: Int) -> NSBezierPath {
        let mid = midAngle(index) * .pi / 180
        let half = step * .pi / 360
        if items.count == 1 {
            // A single option is a full ring.
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - Self.outerRadius, y: center.y - Self.outerRadius,
                                                   width: Self.outerRadius * 2, height: Self.outerRadius * 2))
            ring.append(NSBezierPath(ovalIn: NSRect(x: center.x - Self.innerRadius, y: center.y - Self.innerRadius,
                                                    width: Self.innerRadius * 2, height: Self.innerRadius * 2)).reversed)
            return ring
        }
        return RingGeometry.slice(center: center, inner: Self.innerRadius, outer: Self.outerRadius,
                                  start: mid - half, end: mid + half, gap: Self.gap, corner: Self.cornerRadius)
    }

    private func drawSegment(_ index: Int) {
        let path = segmentPath(index)
        let selected = index == highlighted
        if selected {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = Palette.accentDeep.withAlphaComponent(0.45)
            glow.shadowBlurRadius = 10
            glow.set()
            Palette.accent.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(starting: NSColor.white.withAlphaComponent(0.28), ending: .clear)?
                .draw(in: path, angle: midAngle(index) + 180)
        } else {
            Palette.segment.setFill()
            path.fill()
            Palette.segmentEdge.setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
        drawLabel(for: index, selected: selected)
    }

    private func drawLabel(for index: Int, selected: Bool) {
        let item = items[index]
        let radians = midAngle(index) * .pi / 180
        let radius = (Self.innerRadius + Self.outerRadius) / 2 + 2
        let anchor = NSPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
        let color: NSColor = selected ? NSColor(calibratedWhite: 0.08, alpha: 1) : .labelColor

        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        if let icon = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)?
            .withSymbolConfiguration(config) {
            let size = icon.size
            icon.draw(in: NSRect(x: anchor.x - size.width / 2, y: anchor.y + 3, width: size.width, height: size.height))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let label = NSAttributedString(string: item.title, attributes: [
            .font: NSFont.systemFont(ofSize: items.count > 8 ? 10 : 11, weight: selected ? .semibold : .medium),
            .foregroundColor: selected ? color : NSColor.labelColor.withAlphaComponent(0.85),
            .paragraphStyle: paragraph,
        ])
        let width: CGFloat = min(84, 2 * radius * sin(step * .pi / 360) - 10)
        let height = label.size().height
        label.draw(in: NSRect(x: anchor.x - width / 2, y: anchor.y - height - 2, width: width, height: height))
    }

    private func drawHub() {
        let radius = Self.innerRadius - 8
        let hub = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        hub.fill()
        Palette.hairline.setStroke()
        hub.lineWidth = 0.5
        hub.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let title: String
        if let highlighted { title = items[highlighted].title } else if items.isEmpty { title = "No Options" } else { title = mode.title }
        let titleText = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        let titleHeight = titleText.size().height
        titleText.draw(in: NSRect(x: center.x - radius + 6, y: center.y + 2, width: radius * 2 - 12, height: titleHeight))

        if highlighted != nil {
            let detail = NSAttributedString(string: fileCount == 1 ? "1 file" : "\(fileCount) files", attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ])
            detail.draw(in: NSRect(x: center.x - radius, y: center.y - 16, width: radius * 2, height: 14))
        } else {
            drawKeyHints(below: center.y - 4)
        }
    }

    /// ⇧ ⌘ ⌃ with the active mode's key in a capsule.
    private func drawKeyHints(below top: CGFloat) {
        let width: CGFloat = 20, spacing: CGFloat = 3
        let total = CGFloat(WheelMode.allCases.count) * width + CGFloat(WheelMode.allCases.count - 1) * spacing
        var x = center.x - total / 2
        for mode in WheelMode.allCases {
            let active = mode == self.mode
            let box = NSRect(x: x, y: top - 17, width: width, height: 17)
            if active {
                NSColor.labelColor.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: box, xRadius: 8.5, yRadius: 8.5).fill()
            }
            let glyph = NSAttributedString(string: mode.keyGlyph, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: active ? .semibold : .regular),
                .foregroundColor: active ? NSColor.labelColor : NSColor.tertiaryLabelColor,
            ])
            let size = glyph.size()
            glyph.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
            x += width + spacing
        }
    }

    // MARK: Drop target

    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlighted = index(at: convert(sender.draggingLocation, from: nil))
        return highlighted == nil ? [] : .copy
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { highlighted != nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let highlighted else { return false }
        let item = items[highlighted]
        // Let the drag session finish before running anything that might show UI.
        DispatchQueue.main.async { self.onDrop?(item) }
        return true
    }
}

/// Borderless, non-activating panel that hosts the wheel under the cursor,
/// on a circular glass backing.
final class WheelPanel: NSPanel {
    static let discRadius = WheelView.outerRadius + 10
    static let side: CGFloat = 2 * discRadius + 40
    let wheel = WheelView(frame: NSRect(x: 0, y: 0, width: side, height: side))
    private let container = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        container.wantsLayer = true
        let discFrame = NSRect(x: 20, y: 20, width: Self.discRadius * 2, height: Self.discRadius * 2)
        container.addSubview(Self.makeBacking(frame: discFrame))
        wheel.autoresizingMask = [.width, .height]
        container.addSubview(wheel)
        contentView = container
    }

    /// Liquid Glass on macOS 26 and later; a HUD material disc before that.
    static func makeBacking(frame: NSRect) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = frame.width / 2
            return glass
        }
        let material = NSVisualEffectView(frame: frame)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = NSImage(size: frame.size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return material
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(centeredAt point: NSPoint) {
        setFrameOrigin(NSPoint(x: point.x - Self.side / 2, y: point.y - Self.side / 2))
        alphaValue = 0
        orderFrontRegardless()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion, let layer = container.layer {
            // Grow from the pointer with a gentle spring.
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: Self.side / 2, y: Self.side / 2)
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.fromValue = 0.82
            spring.toValue = 1
            spring.mass = 1
            spring.stiffness = 320
            spring.damping = 24
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: "appear")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.14
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}
