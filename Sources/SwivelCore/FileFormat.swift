import Foundation

/// Broad families of files Swivel knows how to handle.
public enum FileCategory: String, CaseIterable, Sendable {
    case image, audio, video, pdf, document, spreadsheet, subtitle, archive
}

/// Extension bookkeeping: normalization, categories and base names.
public enum FileFormat {
    public static let images: [String] = ["jpg", "png", "heic", "tiff", "gif", "bmp", "webp"]
    public static let audio: [String] = ["mp3", "m4a", "wav", "aiff", "flac", "caf", "ogg", "opus"]
    public static let video: [String] = ["mp4", "mov", "m4v", "mkv", "webm", "avi"]
    public static let documents: [String] = ["docx", "doc", "rtf", "rtfd", "odt", "html", "txt", "md"]
    public static let spreadsheets: [String] = ["csv", "tsv"]
    public static let subtitles: [String] = ["srt", "vtt"]
    public static let archives: [String] = ["zip", "tar", "tgz"]

    static let aliases: [String: String] = [
        "jpeg": "jpg", "jpe": "jpg", "tif": "tiff", "heif": "heic",
        "aif": "aiff", "aifc": "aiff", "htm": "html", "markdown": "md",
        "text": "txt", "gz": "tgz",
    ]

    /// Lowercased, alias-resolved extension. `archive.tar.gz` becomes `tgz`.
    public static func normalizedExtension(of url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") { return "tgz" }
        let ext = url.pathExtension.lowercased()
        return aliases[ext] ?? ext
    }

    public static func category(of ext: String) -> FileCategory? {
        if ext == "pdf" { return .pdf }
        if images.contains(ext) { return .image }
        if audio.contains(ext) { return .audio }
        if video.contains(ext) { return .video }
        if documents.contains(ext) { return .document }
        if spreadsheets.contains(ext) { return .spreadsheet }
        if subtitles.contains(ext) { return .subtitle }
        if archives.contains(ext) { return .archive }
        return nil
    }

    public static func category(of url: URL) -> FileCategory? {
        category(of: normalizedExtension(of: url))
    }

    /// File name without its extension; handles the double `.tar.gz` suffix.
    public static func baseName(of url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        for suffix in [".tar.gz", ".tgz"] where lower.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// The extension written to disk for a target format.
    public static func diskExtension(for target: String) -> String {
        target == "tgz" ? "tar.gz" : target
    }

    /// Short label used on the wheel.
    public static func label(for target: String) -> String {
        switch target {
        case "tgz": return "TAR.GZ"
        case "md": return "MARKDOWN"
        default: return target.uppercased()
        }
    }
}
