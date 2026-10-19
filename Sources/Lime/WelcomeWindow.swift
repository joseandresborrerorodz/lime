import AppKit
import LimeCore
import ServiceManagement
import SwiftUI

/// Shown on first launch and whenever Lime is opened again (Finder, Spotlight,
/// `open`), since a menu-bar app otherwise gives no sign that it's running.
final class WelcomeWindowController {
    private var window: NSWindow?
    var onConvertFiles: (() -> Void)?

    func show() {
        if window == nil {
            let view = WelcomeView(
                capabilities: .detect(),
                convertFiles: { [weak self] in
                    self?.window?.close()
                    self?.onConvertFiles?()
                },
                close: { [weak self] in self?.window?.close() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Lime: File Converter"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // Open on whatever Space the user is looking at, even over a full-screen app.
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            self.window = window
        }
        guard let window else { return }
        window.layoutIfNeeded()
        window.center()
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

private struct WelcomeView: View {
    let capabilities: Capabilities
    let convertFiles: () -> Void
    let close: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: LimeMark.colorImage(size: 84))
            VStack(spacing: 4) {
                Text("Lime: File Converter").font(.title2.bold())
                Text("Lime lives in your menu bar. Start dragging a file, tap a key, and drop it on the wheel.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                KeyRow(key: "⇧", title: "Convert", detail: "Formats that fit the file")
                KeyRow(key: "⌘", title: "Tools", detail: "Compress, rotate, merge, split and more")
                KeyRow(key: "⌃", title: "Actions", detail: "AirDrop, copy, reveal, Terminal, move")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 16) {
                EngineBadge(name: "ffmpeg", found: capabilities.ffmpeg != nil)
                EngineBadge(name: "cwebp", found: capabilities.cwebp != nil)
                Spacer()
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { enabled in
                        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
            .font(.callout)

            HStack {
                Button("Convert Files…", action: convertFiles)
                Spacer()
                Button("Got It", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 22)
        .frame(width: 440)
    }
}

private struct KeyRow: View {
    let key: String, title: String, detail: String

    var body: some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 26)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            Text(title).fontWeight(.semibold).frame(width: 62, alignment: .leading)
            Text(detail).foregroundStyle(.secondary)
        }
    }
}

private struct EngineBadge: View {
    let name: String, found: Bool

    var body: some View {
        Label(name, systemImage: found ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(found ? Color.green : Color.secondary)
            .help(found ? "\(name) is installed" : "Install with: brew install \(name == "cwebp" ? "webp" : name)")
    }
}
