import Foundation

/// Optional command-line engines found on this Mac. Swivel works without them
/// (Apple frameworks cover the basics) and offers more formats when present.
public struct Capabilities: Sendable, Equatable {
    public var ffmpeg: URL?
    public var cwebp: URL?

    public init(ffmpeg: URL? = nil, cwebp: URL? = nil) {
        self.ffmpeg = ffmpeg
        self.cwebp = cwebp
    }

    public static let none = Capabilities()

    public static func detect() -> Capabilities {
        Capabilities(ffmpeg: findExecutable("ffmpeg"), cwebp: findExecutable("cwebp"))
    }

    static func findExecutable(_ name: String) -> URL? {
        var directories = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories += path.split(separator: ":").map(String.init)
        }
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
