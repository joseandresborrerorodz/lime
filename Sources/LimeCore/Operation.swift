import Foundation

/// Editing tools that produce a new file next to the original.
public enum Tool: String, CaseIterable, Sendable {
    case compress
    case stripMetadata
    case halfSize
    case rotate
    case makePDF
    case mergePDF
    case splitPDF
    case muteVideo
    case videoToGIF
    case normalizeAudio
    case extractArchive
    case zip

    public var title: String {
        switch self {
        case .compress: return "Compress"
        case .stripMetadata: return "Strip Metadata"
        case .halfSize: return "Half Size"
        case .rotate: return "Rotate"
        case .makePDF: return "Make PDF"
        case .mergePDF: return "Merge PDFs"
        case .splitPDF: return "Split Pages"
        case .muteVideo: return "Mute"
        case .videoToGIF: return "Make GIF"
        case .normalizeAudio: return "Normalize"
        case .extractArchive: return "Extract"
        case .zip: return "Zip"
        }
    }

    public var symbol: String {
        switch self {
        case .compress: return "arrow.down.forward.and.arrow.up.backward"
        case .stripMetadata: return "eye.slash"
        case .halfSize: return "arrow.down.right.and.arrow.up.left.circle"
        case .rotate: return "rotate.right"
        case .makePDF: return "doc.richtext"
        case .mergePDF: return "doc.on.doc"
        case .splitPDF: return "square.split.2x1"
        case .muteVideo: return "speaker.slash"
        case .videoToGIF: return "photo.stack"
        case .normalizeAudio: return "waveform.path"
        case .extractArchive: return "shippingbox"
        case .zip: return "archivebox"
        }
    }

    /// Word appended to the base name of the result, e.g. "photo compressed.jpg".
    var suffix: String {
        switch self {
        case .compress: return "compressed"
        case .stripMetadata: return "clean"
        case .halfSize: return "half"
        case .rotate: return "rotated"
        case .muteVideo: return "muted"
        case .normalizeAudio: return "normalized"
        case .splitPDF: return "pages"
        default: return ""
        }
    }
}

/// Something the engine can do to a set of files.
public enum Operation: Hashable, Sendable {
    case convert(String)
    case tool(Tool)

    public var title: String {
        switch self {
        case .convert(let target): return FileFormat.label(for: target)
        case .tool(let tool): return tool.title
        }
    }

    public var symbol: String {
        switch self {
        case .convert(let target):
            switch FileFormat.category(of: target) {
            case .image: return "photo"
            case .audio: return "music.note"
            case .video: return "film"
            case .pdf: return "doc.richtext"
            case .document: return "doc.text"
            case .spreadsheet: return "tablecells"
            case .subtitle: return "captions.bubble"
            case .archive: return "archivebox"
            case nil: return "doc"
            }
        case .tool(let tool): return tool.symbol
        }
    }
}
