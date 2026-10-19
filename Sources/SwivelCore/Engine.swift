import Foundation

/// Runs operations synchronously. Call it off the main thread.
public struct Engine: Sendable {
    public let capabilities: Capabilities

    public init(capabilities: Capabilities) {
        self.capabilities = capabilities
    }

    /// Performs `operation` on every input and returns the files it created.
    /// Results are always new files next to the inputs; originals are untouched.
    public func perform(_ operation: Operation, on inputs: [URL]) throws -> [URL] {
        guard !inputs.isEmpty else { return [] }
        switch operation {
        case .convert(let target):
            return try inputs.compactMap { input in
                guard FileFormat.normalizedExtension(of: input) != target else { return nil }
                return try convert(input, to: target)
            }
        case .tool(let tool):
            return try run(tool, on: inputs)
        }
    }

    func convert(_ input: URL, to target: String) throws -> URL {
        let source = FileFormat.normalizedExtension(of: input)
        guard Catalog(capabilities: capabilities).targets(for: source).contains(target) else {
            throw SwivelError.unsupported("\(source.uppercased()) to \(target.uppercased())")
        }
        let category = FileFormat.category(of: source)
        if category == .pdf, FileFormat.category(of: target) == .image {
            return try PDFConversion.toImages(input, ext: target, capabilities: capabilities)
        }
        let output = OutputNaming.conversionURL(for: input, target: target)
        do {
            switch category {
            case .image where target == "mp4":
                try MediaConversion.convert(input, to: target, output: output, capabilities: capabilities)
            case .image:
                try ImageConversion.convert(input, to: target, output: output, capabilities: capabilities)
            case .audio, .video:
                try MediaConversion.convert(input, to: target, output: output, capabilities: capabilities)
            case .pdf:
                try PDFConversion.toText(input, output: output)
            case .document:
                try DocumentConversion.convert(input, to: target, output: output)
            case .spreadsheet:
                let text = try String(contentsOf: input, encoding: .utf8)
                try TextFormats.table(text, from: source, to: target).write(to: output, atomically: true, encoding: .utf8)
            case .subtitle:
                let text = try String(contentsOf: input, encoding: .utf8)
                try TextFormats.subtitles(text, to: target).write(to: output, atomically: true, encoding: .utf8)
            case .archive:
                try ArchiveConversion.convert(input, to: target, output: output)
            case nil:
                throw SwivelError.unsupported(input.lastPathComponent)
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return output
    }

    func run(_ tool: Tool, on inputs: [URL]) throws -> [URL] {
        switch tool {
        case .makePDF: return [try ImageConversion.makePDF(inputs)]
        case .mergePDF: return [try PDFConversion.merge(inputs)]
        case .zip: return [try ArchiveConversion.zip(inputs)]
        default: break
        }
        return try inputs.map { input in
            switch (tool, FileFormat.category(of: input)) {
            case (.compress, .image): return try ImageConversion.compress(input, capabilities: capabilities)
            case (.compress, .video): return try MediaConversion.compressVideo(input, capabilities: capabilities)
            case (.stripMetadata, .image), (.halfSize, .image), (.rotate, .image):
                return try ImageConversion.edit(input, tool: tool, capabilities: capabilities)
            case (.splitPDF, .pdf): return try PDFConversion.split(input)
            case (.muteVideo, .video): return try MediaConversion.mute(input, capabilities: capabilities)
            case (.videoToGIF, .video): return try MediaConversion.gif(input, capabilities: capabilities)
            case (.normalizeAudio, .audio): return try MediaConversion.normalize(input, capabilities: capabilities)
            case (.extractArchive, .archive): return try ArchiveConversion.extract(input)
            default: throw SwivelError.unsupported("\(tool.title) on \(input.lastPathComponent)")
            }
        }
    }
}
