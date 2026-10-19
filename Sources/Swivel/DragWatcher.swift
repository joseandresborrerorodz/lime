import AppKit

/// Which ring the wheel shows.
enum WheelMode: CaseIterable {
    case convert, tools, actions

    var title: String {
        switch self {
        case .convert: return "Convert"
        case .tools: return "Tools"
        case .actions: return "Actions"
        }
    }

    /// The modifier that opens this mode while dragging.
    var key: NSEvent.ModifierFlags {
        switch self {
        case .convert: return .shift
        case .tools: return .command
        case .actions: return .control
        }
    }

    var keyGlyph: String {
        switch self {
        case .convert: return "⇧"
        case .tools: return "⌘"
        case .actions: return "⌃"
        }
    }
}

/// Watches for file drags anywhere on screen and reports when the user taps
/// a wheel key mid-drag.
///
/// Mouse-down is observed with a global monitor (no Accessibility permission
/// needed). While the button is held, a timer polls the modifier keys and the
/// system drag pasteboard, whose change count bumps when a real drag starts.
final class DragWatcher {
    var onKeyTap: ((WheelMode, [URL], NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var monitors: [Any] = []
    private var timer: Timer?
    private var changeCountAtMouseDown = 0
    private var previousFlags: NSEvent.ModifierFlags = []
    private let watchedKeys: NSEvent.ModifierFlags = [.shift, .command, .control, .option]
    private let dragPasteboard = NSPasteboard(name: .drag)

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.mouseDown() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: handler) {
            monitors.append(global)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            handler(event)
            return event
        }
        if let local { monitors.append(local) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        timer?.invalidate()
    }

    private func mouseDown() {
        changeCountAtMouseDown = dragPasteboard.changeCount
        // Keys already held when the drag starts (e.g. ⌥ to copy) don't count as taps.
        previousFlags = NSEvent.modifierFlags.intersection(watchedKeys)
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard NSEvent.pressedMouseButtons & 1 == 1 else {
            timer?.invalidate()
            timer = nil
            onDragEnded?()
            return
        }
        let flags = NSEvent.modifierFlags.intersection(watchedKeys)
        let pressed = flags.subtracting(previousFlags)
        previousFlags = flags
        guard let mode = WheelMode.allCases.first(where: { pressed == $0.key }) else { return }
        guard dragPasteboard.changeCount != changeCountAtMouseDown else { return }
        let files = draggedFiles()
        guard !files.isEmpty else { return }
        onKeyTap?(mode, files, NSEvent.mouseLocation)
    }

    private func draggedFiles() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return dragPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
