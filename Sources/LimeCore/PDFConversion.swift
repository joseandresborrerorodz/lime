import CoreGraphics
import Foundation
import PDFKit

enum PDFConversion {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw LimeError.failed("Could not open \(url.lastPathComponent) as a PDF.")
        }
        if document.isLocked { throw LimeError.failed("\(url.lastPathComponent) is password protected.") }
        return document
    }

    /// Renders a page at 150 DPI on white.
    static func render(_ page: PDFPage, dpi: CGFloat = 150) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72
        let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw LimeError.failed("Could not render PDF page.") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { throw LimeError.failed("Could not render PDF page.") }
        return image
    }

    /// One image for a single page; a folder of images for several pages.
    static func toImages(_ input: URL, ext: String, capabilities: Capabilities) throws -> URL {
        let document = try open(input)
        let count = document.pageCount
        if count == 1, let page = document.page(at: 0) {
            let output = OutputNaming.conversionURL(for: input, target: ext)
            try ImageConversion.write(try render(page), to: output, ext: ext, quality: 0.9, capabilities: capabilities)
            return output
        }
        let folder = OutputNaming.toolURL(for: input, suffix: ext.uppercased(), extension: nil)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<count {
            guard let page = document.page(at: index) else { continue }
            let file = folder.appendingPathComponent("Page \(index + 1).\(ext)")
            try ImageConversion.write(try render(page), to: file, ext: ext, quality: 0.9, capabilities: capabilities)
        }
        return folder
    }

    static func toText(_ input: URL, output: URL) throws {
        let text = try open(input).string ?? ""
        try text.write(to: output, atomically: true, encoding: .utf8)
    }

    static func merge(_ inputs: [URL]) throws -> URL {
        let merged = PDFDocument()
        for input in inputs {
            let document = try open(input)
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) {
                    merged.insert(page, at: merged.pageCount)
                }
            }
        }
        let output = OutputNaming.uniqueURL(
            in: inputs[0].deletingLastPathComponent(), base: "Merged", extension: "pdf")
        guard merged.write(to: output) else { throw LimeError.failed("Could not write merged PDF.") }
        return output
    }

    static func split(_ input: URL) throws -> URL {
        let document = try open(input)
        let folder = OutputNaming.toolURL(for: input, suffix: Tool.splitPDF.suffix, extension: nil)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = FileFormat.baseName(of: input)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            single.write(to: folder.appendingPathComponent("\(base) page \(index + 1).pdf"))
        }
        return folder
    }
}
