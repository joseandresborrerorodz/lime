import AppKit
import SwivelCore

/// Things done with the files themselves rather than to their contents.
enum FileAction: CaseIterable {
    case airDrop, copyFiles, copyPath, reveal, terminal, moveTo

    var title: String {
        switch self {
        case .airDrop: return "AirDrop"
        case .copyFiles: return "Copy"
        case .copyPath: return "Copy Path"
        case .reveal: return "Reveal"
        case .terminal: return "Terminal"
        case .moveTo: return "Move To…"
        }
    }

    var symbol: String {
        switch self {
        case .airDrop: return "dot.radiowaves.left.and.right"
        case .copyFiles: return "doc.on.clipboard"
        case .copyPath: return "link"
        case .reveal: return "magnifyingglass"
        case .terminal: return "apple.terminal"
        case .moveTo: return "folder"
        }
    }

    /// Performs the action and returns a short status message for the HUD.
    func perform(on urls: [URL]) -> String? {
        switch self {
        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
                return "AirDrop is not available."
            }
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: urls)
            return nil
        case .copyFiles:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls as [NSURL])
            return urls.count == 1 ? "Copied \(urls[0].lastPathComponent)" : "Copied \(urls.count) items"
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            return urls.count == 1 ? "Copied path" : "Copied \(urls.count) paths"
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return nil
        case .terminal:
            let folder = Self.folder(containing: urls[0])
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
                return "Terminal was not found."
            }
            NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
            return nil
        case .moveTo:
            return Self.move(urls)
        }
    }

    static func folder(containing url: URL) -> URL {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }

    static func move(_ urls: [URL]) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        panel.message = urls.count == 1 ? "Move \(urls[0].lastPathComponent) to:" : "Move \(urls.count) items to:"
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }
        var moved = 0
        for url in urls {
            let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
            let target = OutputNaming.uniqueURL(
                in: destination, base: url.deletingPathExtension().lastPathComponent, extension: ext)
            if (try? FileManager.default.moveItem(at: url, to: target)) != nil { moved += 1 }
        }
        return moved == urls.count ? "Moved to \(destination.lastPathComponent)" : "Moved \(moved) of \(urls.count)"
    }
}
