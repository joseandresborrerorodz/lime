import AppKit
import Foundation

enum DocumentConversion {
    static let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor.black,
    ]

    static func load(_ url: URL) throws -> NSAttributedString {
        let ext = FileFormat.normalizedExtension(of: url)
        switch ext {
        case "txt":
            let text = try String(contentsOf: url, encoding: .utf8)
            return NSAttributedString(string: text, attributes: bodyAttributes)
        case "md":
            let data = try Data(contentsOf: url)
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            let parsed = try NSMutableAttributedString(markdown: data, options: options, baseURL: url)
            parsed.addAttributes(bodyAttributes, range: NSRange(location: 0, length: parsed.length))
            return parsed
        case "html":
            // HTML import uses WebKit and must run on the main thread.
            return try onMain {
                try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
            }
        default:
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        }
    }

    static func convert(_ input: URL, to ext: String, output: URL) throws {
        let text = try load(input)
        let range = NSRange(location: 0, length: text.length)
        let type: NSAttributedString.DocumentType
        switch ext {
        case "txt":
            try text.string.write(to: output, atomically: true, encoding: .utf8)
            return
        case "pdf":
            try writePDF(text, to: output)
            return
        case "docx": type = .officeOpenXML
        case "doc": type = .docFormat
        case "rtf": type = .rtf
        case "odt": type = .openDocument
        case "html": type = .html
        default: throw LimeError.unsupported("writing \(ext.uppercased()) documents")
        }
        let data = try text.data(from: range, documentAttributes: [.documentType: type])
        try data.write(to: output)
    }

    /// Paginates with TextKit onto US Letter pages with one-inch margins.
    static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 72
        let containerSize = CGSize(width: page.width - margin * 2, height: page.height - margin * 2)
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else {
            throw LimeError.failed("Could not create \(url.lastPathComponent).")
        }
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        var containers: [NSTextContainer] = []
        while true {
            let container = NSTextContainer(size: containerSize)
            layout.addTextContainer(container)
            containers.append(container)
            let range = layout.glyphRange(for: container)
            if range.length == 0 || NSMaxRange(range) >= layout.numberOfGlyphs { break }
        }

        for container in containers {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: page.height)
            context.scaleBy(x: 1, y: -1)
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let range = layout.glyphRange(for: container)
            let origin = CGPoint(x: margin, y: margin)
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            NSGraphicsContext.current = previous
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
    }
}
