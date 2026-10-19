import AppKit
import LimeCore

// `Lime --snapshot out.png [light|dark]` renders a sample wheel, for docs and visual checks.
// Live glass blurs what's behind the window, so the preview uses a flat stand-in disc.
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), flag + 1 < CommandLine.arguments.count {
    let dark = CommandLine.arguments.dropFirst(flag + 2).first == "dark"
    let side = WheelPanel.side
    let backdrop = NSImageView(frame: NSRect(x: 0, y: 0, width: side, height: side))
    backdrop.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    // A wallpaper-like backdrop so the glass has something to show through.
    backdrop.image = NSImage(size: backdrop.bounds.size, flipped: false) { rect in
        let colors: [NSColor] = dark
            ? [NSColor(srgbRed: 0.10, green: 0.12, blue: 0.30, alpha: 1), NSColor(srgbRed: 0.35, green: 0.10, blue: 0.35, alpha: 1)]
            : [NSColor(srgbRed: 0.45, green: 0.70, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.98, green: 0.62, blue: 0.70, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: rect, angle: -45)
        for (x, y, r, c) in [(0.25, 0.7, 90.0, NSColor.systemOrange), (0.75, 0.3, 110.0, NSColor.systemTeal)] {
            c.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.width * x - r, y: rect.height * y - r, width: r * 2, height: r * 2)).fill()
        }
        return true
    }
    backdrop.imageScaling = .scaleAxesIndependently
    let disc = NSBox(frame: NSRect(x: 20, y: 20, width: WheelPanel.discRadius * 2, height: WheelPanel.discRadius * 2))
    disc.boxType = .custom
    disc.cornerRadius = WheelPanel.discRadius
    disc.borderWidth = 0
    disc.fillColor = dark ? NSColor(white: 0.05, alpha: 0.35) : NSColor(white: 1, alpha: 0.3)
    backdrop.addSubview(disc)
    let view = WheelView(frame: backdrop.bounds)
    view.items = ["jpg", "heic", "tiff", "gif", "bmp", "webp", "pdf"].map { WheelItem(.convert($0)) }
    view.mode = .convert
    view.highlighted = 1
    backdrop.addSubview(view)
    if let rep = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) {
        backdrop.cacheDisplay(in: backdrop.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
    }
    exit(0)
}

// `Lime --icon out.png` renders the 1024 px app icon (used by scripts/make-icon.sh).
if let flag = CommandLine.arguments.firstIndex(of: "--icon"), flag + 1 < CommandLine.arguments.count {
    try? LimeMark.appIconPNG()?.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
