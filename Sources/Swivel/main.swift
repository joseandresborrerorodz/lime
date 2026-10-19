import AppKit
import SwivelCore

// `Swivel --snapshot out.png` renders a sample wheel, for docs and visual checks.
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), flag + 1 < CommandLine.arguments.count {
    let side = WheelPanel.side
    let view = WheelView(frame: NSRect(x: 0, y: 0, width: side, height: side))
    view.items = ["jpg", "heic", "tiff", "gif", "bmp", "webp", "pdf"].map { WheelItem(.convert($0)) }
    view.mode = .convert
    if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
