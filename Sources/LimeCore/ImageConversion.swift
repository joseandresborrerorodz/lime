import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageConversion {
    static func utType(for ext: String) -> UTType? {
        switch ext {
        case "jpg": return .jpeg
        case "png": return .png
        case "heic": return .heic
        case "tiff": return .tiff
        case "gif": return .gif
        case "bmp": return .bmp
        default: return nil
        }
    }

    static func source(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { throw LimeError.failed("Could not read \(url.lastPathComponent) as an image.") }
        return source
    }

    /// The first frame with its EXIF orientation applied, optionally scaled.
    static func orientedImage(_ url: URL, scale: CGFloat = 1) throws -> CGImage {
        let src = try source(url)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let width = props[kCGImagePropertyPixelWidth] as? CGFloat ?? 4096
        let height = props[kCGImagePropertyPixelHeight] as? CGFloat ?? 4096
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int((max(width, height) * scale).rounded())),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw LimeError.failed("Could not decode \(url.lastPathComponent).")
        }
        return image
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// Draws the image over white, for formats without transparency.
    static func flattened(_ image: CGImage) -> CGImage {
        guard hasAlpha(image),
              let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    static func write(
        _ image: CGImage, to url: URL, ext: String,
        properties: [CFString: Any] = [:], quality: Double? = nil,
        capabilities: Capabilities
    ) throws {
        if ext == "webp" {
            try writeWebP(image, to: url, quality: quality ?? 0.85, capabilities: capabilities)
            return
        }
        if ext == "pdf" {
            try writePDF([image], to: url)
            return
        }
        guard let type = utType(for: ext),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw LimeError.unsupported("writing \(ext.uppercased()) images") }
        var props = properties
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        let pixels = ["jpg", "bmp"].contains(ext) ? flattened(image) : image
        CGImageDestinationAddImage(destination, pixels, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LimeError.failed("Could not write \(url.lastPathComponent).")
        }
    }

    static func writeWebP(_ image: CGImage, to url: URL, quality: Double, capabilities: Capabilities) throws {
        guard let cwebp = capabilities.cwebp else { throw LimeError.missingTool("webp") }
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let png = scratch.appendingPathComponent("frame.png")
        try write(image, to: png, ext: "png", capabilities: capabilities)
        try ProcessRunner.run(cwebp, ["-quiet", "-q", String(Int(quality * 100)), png.path, "-o", url.path])
    }

    /// One page per image, each page the size of its image.
    static func writePDF(_ images: [CGImage], to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { throw LimeError.failed("Could not create \(url.lastPathComponent).") }
        for image in images {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.beginPage(mediaBox: &box)
            context.draw(image, in: box)
            context.endPage()
        }
        context.closePDF()
    }

    // MARK: Operations

    /// Format conversion that keeps metadata and orientation.
    static func convert(_ input: URL, to ext: String, output: URL, capabilities: Capabilities) throws {
        if ext == "webp" || ext == "pdf" {
            try write(try orientedImage(input), to: output, ext: ext, capabilities: capabilities)
            return
        }
        let src = try source(input)
        guard let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw LimeError.failed("Could not decode \(input.lastPathComponent).")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        try write(image, to: output, ext: ext, properties: props, quality: 0.9, capabilities: capabilities)
    }

    /// Output format for edits: keep the input format when Lime can write it.
    static func editFormat(for input: URL, capabilities: Capabilities) -> String {
        let ext = FileFormat.normalizedExtension(of: input)
        if utType(for: ext) != nil { return ext }
        if ext == "webp" && capabilities.cwebp != nil { return ext }
        return "png"
    }

    static func compress(_ input: URL, capabilities: Capabilities) throws -> URL {
        var ext = editFormat(for: input, capabilities: capabilities)
        if !["jpg", "heic", "webp"].contains(ext) { ext = "jpg" }
        let output = OutputNaming.toolURL(for: input, suffix: Tool.compress.suffix, extension: ext)
        try write(try orientedImage(input), to: output, ext: ext, quality: 0.6, capabilities: capabilities)
        return output
    }

    /// Re-encodes the pixels only, so EXIF, GPS and other metadata are gone.
    static func edit(_ input: URL, tool: Tool, capabilities: Capabilities) throws -> URL {
        let ext = editFormat(for: input, capabilities: capabilities)
        let output = OutputNaming.toolURL(for: input, suffix: tool.suffix, extension: ext)
        var image = try orientedImage(input, scale: tool == .halfSize ? 0.5 : 1)
        if tool == .rotate { image = try rotatedClockwise(image) }
        try write(image, to: output, ext: ext, quality: 0.92, capabilities: capabilities)
        return output
    }

    static func rotatedClockwise(_ image: CGImage) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: image.height, height: image.width, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw LimeError.failed("Could not rotate image.") }
        context.translateBy(x: 0, y: CGFloat(image.width))
        context.rotate(by: -.pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let rotated = context.makeImage() else { throw LimeError.failed("Could not rotate image.") }
        return rotated
    }

    static func makePDF(_ inputs: [URL]) throws -> URL {
        let images = try inputs.map { try orientedImage($0) }
        let output = OutputNaming.uniqueURL(
            in: inputs[0].deletingLastPathComponent(), base: "Images", extension: "pdf")
        try writePDF(images, to: output)
        return output
    }
}
