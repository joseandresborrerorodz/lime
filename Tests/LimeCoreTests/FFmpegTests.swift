import Foundation
import Testing
@testable import LimeCore

/// Runs every ffmpeg-backed conversion and tool against the installed ffmpeg.
/// Skipped when ffmpeg isn't installed.
@Suite(.enabled(if: Capabilities.detect().ffmpeg != nil, "needs ffmpeg"))
struct FFmpegTests {
    let capabilities = Capabilities.detect()
    var engine: Engine { Engine(capabilities: capabilities) }
    var catalog: Catalog { Catalog(capabilities: capabilities) }

    /// A one-second test pattern with a tone, made by ffmpeg itself.
    func makeClip(in dir: URL) throws -> URL {
        let clip = dir.appendingPathComponent("clip.mp4")
        try ProcessRunner.run(capabilities.ffmpeg!, MediaConversion.quiet + [
            "-f", "lavfi", "-i", "testsrc=size=320x240:rate=24:duration=1",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-c:v", "h264_videotoolbox", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", clip.path,
        ])
        return clip
    }

    func assertNonEmpty(_ urls: [URL], _ label: String) throws {
        let url = try #require(urls.first, "\(label) produced nothing")
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 0, "\(label) wrote an empty file")
    }

    @Test func everyVideoTargetAndTool() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clip = try makeClip(in: dir)
        for target in catalog.conversions(for: [clip]) {
            try assertNonEmpty(try engine.perform(.convert(target), on: [clip]), "mp4 → \(target)")
        }
        for tool in catalog.tools(for: [clip]) {
            try assertNonEmpty(try engine.perform(.tool(tool), on: [clip]), tool.title)
        }
    }

    @Test func everyAudioTargetAndTool() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clip = try makeClip(in: dir)
        let mp3 = try #require(try engine.perform(.convert("mp3"), on: [clip]).first)
        for target in catalog.conversions(for: [mp3]) {
            let outputs = try engine.perform(.convert(target), on: [mp3])
            try assertNonEmpty(outputs, "mp3 → \(target)")
            // Each output must decode back again (catches wrong container/codec pairs).
            try ProcessRunner.run(capabilities.ffmpeg!, MediaConversion.quiet + ["-i", outputs[0].path, "-f", "null", "-"])
        }
        try assertNonEmpty(try engine.perform(.tool(.normalizeAudio), on: [mp3]), "Normalize")
    }

    @Test func gifToVideo() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gif = try #require(try engine.perform(.tool(.videoToGIF), on: [try makeClip(in: dir)]).first)
        try assertNonEmpty(try engine.perform(.convert("mp4"), on: [gif]), "gif → mp4")
    }
}
