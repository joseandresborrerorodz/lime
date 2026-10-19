import AVFoundation
import Foundation

/// Audio and video. Uses ffmpeg when installed, otherwise AVFoundation.
enum MediaConversion {
    static let quiet = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y"]

    static func encoderArguments(for target: String) -> [String] {
        let h264 = ["-c:v", "h264_videotoolbox", "-q:v", "65", "-pix_fmt", "yuv420p",
                    "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]
        switch target {
        case "mp4", "m4v": return h264 + ["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case "mov", "mkv": return h264 + ["-c:a", "aac", "-b:a", "192k"]
        case "webm": return ["-c:v", "libvpx-vp9", "-crf", "33", "-b:v", "0", "-c:a", "libopus", "-b:a", "128k"]
        case "avi": return ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame", "-q:a", "3"]
        case "gif": return ["-an", "-vf", gifFilter, "-loop", "0"]
        case "mp3": return ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case "m4a": return ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case "wav", "caf": return ["-vn", "-c:a", "pcm_s16le"]
        case "aiff": return ["-vn", "-c:a", "pcm_s16be"]
        case "flac": return ["-vn", "-c:a", "flac"]
        case "ogg": return ["-vn", "-c:a", "libvorbis", "-q:a", "5"]
        case "opus": return ["-vn", "-c:a", "libopus", "-b:a", "128k"]
        default: return []
        }
    }

    static let gifFilter = "fps=12,scale='min(720,iw)':-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"

    static func ffmpeg(_ capabilities: Capabilities, _ arguments: [String]) throws {
        guard let ffmpeg = capabilities.ffmpeg else { throw LimeError.missingTool("ffmpeg") }
        try ProcessRunner.run(ffmpeg, quiet + arguments)
    }

    static func convert(_ input: URL, to target: String, output: URL, capabilities: Capabilities) throws {
        if capabilities.ffmpeg != nil {
            try ffmpeg(capabilities, ["-i", input.path] + encoderArguments(for: target) + [output.path])
            return
        }
        switch target {
        case "mp4", "mov", "m4v":
            try export(AVURLAsset(url: input), preset: AVAssetExportPresetHighestQuality, to: output, type: fileType(for: target))
        case "m4a":
            try export(AVURLAsset(url: input), preset: AVAssetExportPresetAppleM4A, to: output, type: .m4a)
        case "wav", "aiff", "caf":
            try writePCM(input, to: output, bigEndian: target == "aiff")
        default:
            throw LimeError.missingTool("ffmpeg")
        }
    }

    static func fileType(for ext: String) -> AVFileType {
        switch ext {
        case "mp4": return .mp4
        case "m4v": return .m4v
        case "m4a": return .m4a
        default: return .mov
        }
    }

    static func export(_ asset: AVAsset, preset: String, to output: URL, type: AVFileType) throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw LimeError.unsupported("this media with AVFoundation")
        }
        session.outputURL = output
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        let done = DispatchSemaphore(value: 0)
        session.exportAsynchronously { done.signal() }
        done.wait()
        if session.status != .completed {
            try? FileManager.default.removeItem(at: output)
            throw LimeError.failed(session.error?.localizedDescription ?? "Export failed.")
        }
    }

    /// Decodes any AVFoundation-readable audio into 16-bit PCM WAV/AIFF/CAF.
    static func writePCM(_ input: URL, to output: URL, bigEndian: Bool) throws {
        let source = try AVAudioFile(forReading: input)
        let format = source.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: bigEndian,
        ]
        let destination = try AVAudioFile(
            forWriting: output, settings: settings,
            commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
            throw LimeError.failed("Could not allocate an audio buffer.")
        }
        while source.framePosition < source.length {
            try source.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try destination.write(from: buffer)
        }
    }

    // MARK: Tools

    static func sameFormatOutput(_ input: URL, tool: Tool) -> (URL, String) {
        let ext = FileFormat.normalizedExtension(of: input)
        return (OutputNaming.toolURL(for: input, suffix: tool.suffix, extension: ext), ext)
    }

    static func mute(_ input: URL, capabilities: Capabilities) throws -> URL {
        let (output, ext) = sameFormatOutput(input, tool: .muteVideo)
        if capabilities.ffmpeg != nil {
            try ffmpeg(capabilities, ["-i", input.path, "-map", "0:v", "-c", "copy", "-an", output.path])
            return output
        }
        let asset = AVURLAsset(url: input)
        let composition = AVMutableComposition()
        let duration = CMTimeRange(start: .zero, duration: asset.duration)
        for track in asset.tracks(withMediaType: .video) {
            let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try copy?.insertTimeRange(duration, of: track, at: .zero)
            copy?.preferredTransform = track.preferredTransform
        }
        try export(composition, preset: AVAssetExportPresetPassthrough, to: output, type: fileType(for: ext))
        return output
    }

    static func compressVideo(_ input: URL, capabilities: Capabilities) throws -> URL {
        let output = OutputNaming.toolURL(for: input, suffix: Tool.compress.suffix, extension: "mp4")
        if capabilities.ffmpeg != nil {
            try ffmpeg(capabilities, [
                "-i", input.path, "-c:v", "hevc_videotoolbox", "-q:v", "50", "-tag:v", "hvc1",
                "-vf", "scale='min(1920,iw)':-2", "-c:a", "aac", "-b:a", "128k",
                "-movflags", "+faststart", output.path,
            ])
            return output
        }
        try export(AVURLAsset(url: input), preset: AVAssetExportPresetHEVC1920x1080, to: output, type: .mp4)
        return output
    }

    static func gif(_ input: URL, capabilities: Capabilities) throws -> URL {
        let output = OutputNaming.conversionURL(for: input, target: "gif")
        try ffmpeg(capabilities, ["-i", input.path] + encoderArguments(for: "gif") + [output.path])
        return output
    }

    static func normalize(_ input: URL, capabilities: Capabilities) throws -> URL {
        let (output, ext) = sameFormatOutput(input, tool: .normalizeAudio)
        try ffmpeg(capabilities, [
            "-i", input.path, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
        ] + encoderArguments(for: ext) + [output.path])
        return output
    }
}
