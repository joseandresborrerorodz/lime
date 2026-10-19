import AppKit
import ServiceManagement
import LimeCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let watcher = DragWatcher()
    private let panel = WheelPanel()
    private let hud = HUD()
    private let welcome = WelcomeWindowController()
    private let work = DispatchQueue(label: "lime.engine", qos: .userInitiated)
    private var capabilities = Capabilities.detect()
    private var files: [URL] = []
    private var lastResults: [URL] = []

    private var soundsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sounds") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = LimeMark.menuBarImage()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        panel.wheel.onDrop = { [weak self] item in self?.handle(item) }
        panel.wheel.onHighlight = { [weak self] in self?.play("Tink", volume: 0.15) }
        watcher.onKeyTap = { [weak self] mode, files, point in self?.showWheel(mode, files: files, at: point) }
        watcher.onDragEnded = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self?.panel.dismiss() }
        }
        watcher.start()

        welcome.onConvertFiles = { [weak self] in self?.chooseFiles() }
        if !UserDefaults.standard.bool(forKey: "hasShownWelcome") {
            UserDefaults.standard.set(true, forKey: "hasShownWelcome")
            welcome.show()
        }
    }

    /// Opening Lime again (Finder, Spotlight, `open`) shows the welcome window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        welcome.show()
        return true
    }

    // MARK: Wheel

    private func items(for mode: WheelMode, files: [URL]) -> [WheelItem] {
        let catalog = Catalog(capabilities: capabilities)
        switch mode {
        case .convert: return catalog.conversions(for: files).map { WheelItem(.convert($0)) }
        case .tools: return catalog.tools(for: files).map { WheelItem(.tool($0)) }
        case .actions: return FileAction.allCases.map(WheelItem.init)
        }
    }

    private func showWheel(_ mode: WheelMode, files: [URL], at point: NSPoint) {
        if !panel.isVisible { capabilities = .detect() }
        self.files = files
        panel.wheel.mode = mode
        panel.wheel.fileCount = files.count
        panel.wheel.items = items(for: mode, files: files)
        if !panel.isVisible { panel.show(centeredAt: point) }
    }

    private func handle(_ item: WheelItem) {
        panel.dismiss()
        perform(item, on: files)
    }

    private func perform(_ item: WheelItem, on files: [URL]) {
        switch item.kind {
        case .action(let action):
            if let message = action.perform(on: files) { hud.show(message) }
        case .operation(let operation):
            run(operation, on: files)
        }
    }

    private func run(_ operation: LimeCore.Operation, on files: [URL]) {
        let verb: String
        if case .convert(let target) = operation { verb = "Converting to \(FileFormat.label(for: target))" } else { verb = operation.title }
        hud.show("\(verb)…", busy: true, hideAfter: nil)
        let engine = Engine(capabilities: capabilities)
        work.async {
            let result = Result { try engine.perform(operation, on: files) }
            DispatchQueue.main.async { self.finish(result) }
        }
    }

    private func finish(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let outputs) where outputs.isEmpty:
            hud.show("Already in that format")
        case .success(let outputs):
            lastResults = outputs
            hud.show(outputs.count == 1 ? "Saved \(outputs[0].lastPathComponent)" : "Saved \(outputs.count) files")
            play("Glass", volume: 0.3)
        case .failure(let error):
            hud.show(error.localizedDescription, hideAfter: 5)
            play("Basso", volume: 0.4)
        }
    }

    private func play(_ name: String, volume: Float) {
        guard soundsEnabled, let sound = NSSound(named: name) else { return }
        sound.volume = volume
        sound.play()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        capabilities = .detect()
        menu.removeAllItems()
        let hint = NSMenuItem(title: "Drag files, then tap ⇧ Convert · ⌘ Tools · ⌃ Actions", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(item("Convert Files…", #selector(chooseFiles), key: "o"))
        let reveal = item("Reveal Last Result", #selector(revealLast))
        reveal.isEnabled = !lastResults.isEmpty
        menu.addItem(reveal)
        menu.addItem(.separator())

        for (name, url) in [("ffmpeg", capabilities.ffmpeg), ("cwebp", capabilities.cwebp)] {
            let title = url == nil ? "\(name): not found (click to copy install command)" : "\(name): \(url!.path)"
            let row = item(title, url == nil ? #selector(copyInstallCommand(_:)) : nil)
            row.representedObject = name == "cwebp" ? "webp" : name
            row.isEnabled = url == nil
            menu.addItem(row)
        }
        menu.addItem(.separator())

        let sounds = item("Play Sounds", #selector(toggleSounds))
        sounds.state = soundsEnabled ? .on : .off
        menu.addItem(sounds)
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("About Lime", #selector(about)))
        menu.addItem(item("Quit Lime", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return item
    }

    /// Keyboard/menu path to the same operations, for when dragging isn't handy.
    @objc func chooseFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let open = NSOpenPanel()
        open.allowsMultipleSelection = true
        open.canChooseDirectories = true
        open.prompt = "Choose"
        guard open.runModal() == .OK, !open.urls.isEmpty else { return }
        let chosen = open.urls
        capabilities = .detect()

        let menu = NSMenu()
        for mode in WheelMode.allCases {
            let header = NSMenuItem(title: mode.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let entries = items(for: mode, files: chosen)
            if entries.isEmpty {
                let none = NSMenuItem(title: "  None for this selection", action: nil, keyEquivalent: "")
                none.isEnabled = false
                menu.addItem(none)
            }
            for entry in entries {
                let row = NSMenuItem(title: entry.title, action: #selector(pickedFromMenu(_:)), keyEquivalent: "")
                row.target = self
                row.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
                row.representedObject = MenuChoice(item: entry, files: chosen)
                menu.addItem(row)
            }
            menu.addItem(.separator())
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private final class MenuChoice {
        let item: WheelItem
        let files: [URL]
        init(item: WheelItem, files: [URL]) { self.item = item; self.files = files }
    }

    @objc private func pickedFromMenu(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? MenuChoice else { return }
        perform(choice.item, on: choice.files)
    }

    @objc private func revealLast() {
        NSWorkspace.shared.activateFileViewerSelecting(lastResults)
    }

    @objc private func copyInstallCommand(_ sender: NSMenuItem) {
        let formula = sender.representedObject as? String ?? "ffmpeg"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install \(formula)", forType: .string)
        hud.show("Copied: brew install \(formula)")
    }

    @objc private func toggleSounds() { soundsEnabled.toggle() }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            hud.show("Launch at Login needs Lime.app in Applications.", hideAfter: 4)
        }
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Open-source drag-and-tap file converter.\nEverything runs on your Mac."),
        ])
    }
}
