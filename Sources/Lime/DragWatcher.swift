import AppKit
import os

let dragLog = Logger(subsystem: "io.github.joseandresborrerorodz.Lime", category: "drag")

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
            dragLog.notice("global mouse-down monitor installed")
        } else {
            dragLog.error("global mouse-down monitor could not be installed")
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
        dragLog.notice("mouse down; drag pasteboard count \(self.changeCountAtMouseDown)")
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
        let count = dragPasteboard.changeCount
        dragLog.notice("key tap \(mode.title, privacy: .public); pasteboard count \(count) (was \(self.changeCountAtMouseDown))")
        guard count != changeCountAtMouseDown else {
            dragLog.notice("ignored: no drag session started since mouse down")
            return
        }
        let files = draggedFiles()
        dragLog.notice("drag carries \(files.count) file(s); types \(self.dragPasteboard.types?.map(\.rawValue).joined(separator: ",") ?? "none", privacy: .public)")
        guard !files.isEmpty else { return }
        onKeyTap?(mode, files, NSEvent.mouseLocation)
    }

    private func draggedFiles() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return dragPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
