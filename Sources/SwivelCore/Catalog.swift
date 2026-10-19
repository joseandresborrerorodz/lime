import Foundation

/// Decides which conversions and tools to offer for a selection of files.
public struct Catalog: Sendable {
    public let capabilities: Capabilities

    public init(capabilities: Capabilities) {
        self.capabilities = capabilities
    }

    /// Output formats offered for one input format, including the input format
    /// itself when it is a valid output (callers filter it out).
    public func targets(for ext: String) -> [String] {
        let ffmpeg = capabilities.ffmpeg != nil
        switch FileFormat.category(of: ext) {
        case .image:
            var result = ["jpg", "png", "heic", "tiff", "gif", "bmp"]
            if capabilities.cwebp != nil { result.append("webp") }
            result.append("pdf")
            if ext == "gif" && ffmpeg { result.append("mp4") }
            return result
        case .audio:
            let nativeInputs = ["mp3", "m4a", "wav", "aiff", "flac", "caf"]
            if ffmpeg { return ["mp3", "m4a", "wav", "aiff", "flac", "ogg", "opus", "caf"] }
            return nativeInputs.contains(ext) ? ["m4a", "wav", "aiff", "caf"] : []
        case .video:
            if ffmpeg { return ["mp4", "mov", "m4v", "mkv", "webm", "avi", "gif", "mp3", "m4a", "wav"] }
            return ["mp4", "mov", "m4v"].contains(ext) ? ["mp4", "mov", "m4v", "m4a"] : []
        case .pdf:
            return ["png", "jpg", "heic", "tiff", "txt"]
        case .document:
            return ["docx", "doc", "rtf", "odt", "html", "txt", "pdf"]
        case .spreadsheet:
            return ["csv", "tsv"]
        case .subtitle:
            return ["srt", "vtt", "txt"]
        case .archive:
            return ["zip", "tgz", "tar"]
        case nil:
            return []
        }
    }

    /// Formats every file in the selection can be converted to. A format is
    /// dropped when all the files are already in it.
    public func conversions(for urls: [URL]) -> [String] {
        let extensions = urls.map(FileFormat.normalizedExtension(of:))
        guard let first = extensions.first else { return [] }
        var result = targets(for: first)
        for ext in extensions.dropFirst() {
            let allowed = Set(targets(for: ext))
            result.removeAll { !allowed.contains($0) }
        }
        let inputs = Set(extensions)
        if inputs.count == 1 { result.removeAll { inputs.contains($0) } }
        return result
    }

    /// Tools offered for the selection, in a stable order.
    public func tools(for urls: [URL]) -> [Tool] {
        guard !urls.isEmpty else { return [] }
        let categories = urls.map { url -> FileCategory? in
            isDirectory(url) ? nil : FileFormat.category(of: url)
        }
        let multiple = urls.count > 1
        var sets = categories.map { category -> Set<Tool> in
            toolSet(for: category, multiple: multiple)
        }
        let shared = sets.removeFirst()
        let intersection = sets.reduce(shared) { $0.intersection($1) }
        return Tool.allCases.filter { intersection.contains($0) }
    }

    private func toolSet(for category: FileCategory?, multiple: Bool) -> Set<Tool> {
        let ffmpeg = capabilities.ffmpeg != nil
        var tools: Set<Tool> = [.zip]
        switch category {
        case .image:
            tools.formUnion([.compress, .stripMetadata, .halfSize, .rotate])
            if multiple { tools.insert(.makePDF) }
        case .pdf:
            tools.insert(multiple ? .mergePDF : .splitPDF)
        case .video:
            tools.formUnion([.compress, .muteVideo])
            if ffmpeg { tools.insert(.videoToGIF) }
        case .audio:
            if ffmpeg { tools.insert(.normalizeAudio) }
        case .archive:
            tools.insert(.extractArchive)
        default:
            break
        }
        return tools
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        // .rtfd bundles are directories but behave as documents.
        return exists && isDir.boolValue && FileFormat.normalizedExtension(of: url) != "rtfd"
    }
}
