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

enum Palette {
    static let accent = NSColor(calibratedRed: 0.62, green: 0.90, blue: 0.10, alpha: 1)
    static let disc = NSColor(calibratedWhite: 0.07, alpha: 0.86)
    static let segment = NSColor(calibratedWhite: 1, alpha: 0.09)
    static let hub = NSColor(calibratedWhite: 0.03, alpha: 0.9)
    static let text = NSColor(calibratedWhite: 1, alpha: 0.92)
    static let dimText = NSColor(calibratedWhite: 1, alpha: 0.5)
}

/// A ring of drop targets. Segments start at 12 o'clock and run clockwise;
/// the hub in the middle is a cancel zone.
final class WheelView: NSView {
    static let outerRadius: CGFloat = 150
    static let innerRadius: CGFloat = 60
    static let gapDegrees: CGFloat = 2.5

    var items: [WheelItem] = [] {
        didSet { highlighted = nil; needsDisplay = true }
    }
    var mode: WheelMode = .convert { didSet { needsDisplay = true } }
    var fileCount = 1 { didSet { needsDisplay = true } }

    var onDrop: ((WheelItem) -> Void)?
    var onHighlight: (() -> Void)?

    private(set) var highlighted: Int? {
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
        let discRadius = Self.outerRadius + 8
        Palette.disc.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - discRadius, y: center.y - discRadius,
                                    width: discRadius * 2, height: discRadius * 2)).fill()

        for index in items.indices {
            let path = segmentPath(index)
            (index == highlighted ? Palette.accent : Palette.segment).setFill()
            path.fill()
            drawLabel(for: index)
        }
        drawHub()
    }

    private func segmentPath(_ index: Int) -> NSBezierPath {
        let gap = items.count > 1 ? Self.gapDegrees : 0
        let start = midAngle(index) + step / 2 - gap / 2
        let end = midAngle(index) - step / 2 + gap / 2
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: Self.outerRadius, startAngle: start, endAngle: end, clockwise: true)
        path.appendArc(withCenter: center, radius: Self.innerRadius, startAngle: end, endAngle: start, clockwise: false)
        path.close()
        return path
    }

    private func drawLabel(for index: Int) {
        let item = items[index]
        let radians = midAngle(index) * .pi / 180
        let radius = (Self.innerRadius + Self.outerRadius) / 2 + 4
        let anchor = NSPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
        let selected = index == highlighted
        let color = selected ? NSColor.black : Palette.text

        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        if let icon = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)?
            .withSymbolConfiguration(config) {
            let size = icon.size
            icon.draw(in: NSRect(x: anchor.x - size.width / 2, y: anchor.y + 2, width: size.width, height: size.height))
        }

        let fontSize: CGFloat = items.count > 8 ? 8.5 : 9.5
        let label = NSAttributedString(string: item.title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
            .kern: 0.4,
        ])
        let size = label.size()
        label.draw(at: NSPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height - 1))
    }

    private func drawHub() {
        let radius = Self.innerRadius - 6
        Palette.hub.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()

        let title: String
        if let highlighted { title = items[highlighted].title } else if items.isEmpty { title = "Nothing here" } else { title = mode.title }
        let titleText = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: highlighted == nil ? Palette.text : Palette.accent,
        ])
        let detail = highlighted == nil
            ? WheelMode.allCases.map { $0 == mode ? "[\($0.keyGlyph)]" : $0.keyGlyph }.joined(separator: " ")
            : (fileCount == 1 ? "1 file" : "\(fileCount) files")
        let detailText = NSAttributedString(string: detail, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: Palette.dimText,
        ])
        let titleSize = titleText.size(), detailSize = detailText.size()
        let maxWidth = radius * 2 - 10
        titleText.draw(in: NSRect(x: center.x - min(titleSize.width, maxWidth) / 2, y: center.y + 1,
                                  width: min(titleSize.width, maxWidth), height: titleSize.height))
        detailText.draw(at: NSPoint(x: center.x - detailSize.width / 2, y: center.y - detailSize.height - 1))
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

/// Borderless, non-activating panel that hosts the wheel under the cursor.
final class WheelPanel: NSPanel {
    static let side: CGFloat = 2 * (WheelView.outerRadius + 12)
    let wheel = WheelView(frame: NSRect(x: 0, y: 0, width: side, height: side))

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
        contentView = wheel
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(centeredAt point: NSPoint) {
        setFrameOrigin(NSPoint(x: point.x - Self.side / 2, y: point.y - Self.side / 2))
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}
