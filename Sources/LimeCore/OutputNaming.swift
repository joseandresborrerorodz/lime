import Foundation

/// Picks result names that never overwrite anything: `photo.png`, then
/// `photo 2.png`, `photo 3.png`, ...
public enum OutputNaming {
    public static func uniqueURL(
        in directory: URL,
        base: String,
        extension ext: String?,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        func make(_ name: String) -> URL {
            let file = ext.map { "\(name).\($0)" } ?? name
            return directory.appendingPathComponent(file, isDirectory: ext == nil)
        }
        var candidate = make(base)
        var counter = 2
        while exists(candidate) {
            candidate = make("\(base) \(counter)")
            counter += 1
        }
        return candidate
    }

    /// Destination for converting `input` into `target`, next to the input.
    public static func conversionURL(for input: URL, target: String) -> URL {
        uniqueURL(
            in: input.deletingLastPathComponent(),
            base: FileFormat.baseName(of: input),
            extension: FileFormat.diskExtension(for: target)
        )
    }

    /// Destination for a tool result, e.g. `photo compressed.jpg`.
    public static func toolURL(for input: URL, suffix: String, extension ext: String?) -> URL {
        let base = FileFormat.baseName(of: input)
        return uniqueURL(
            in: input.deletingLastPathComponent(),
            base: suffix.isEmpty ? base : "\(base) \(suffix)",
            extension: ext
        )
    }
}
