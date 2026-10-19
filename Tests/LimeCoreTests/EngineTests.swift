import AppKit
import AVFoundation
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import LimeCore

/// End-to-end conversions on generated files, using only Apple frameworks.
@Suite struct EngineTests {
    let engine = Engine(capabilities: .none)

    func scratch() throws -> URL { try makeScratchDirectory() }

    func makePNG(in dir: URL, name: String = "dot.png", width: Int = 40, height: Int = 20) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.4, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let url = dir.appendingPathComponent(name)
        try ImageConversion.write(context.makeImage()!, to: url, ext: "png", capabilities: .none)
        return url
    }

    func pixelSize(_ url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }

    @Test func imageConversionsAndTools() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try makePNG(in: dir)

        let jpg = try #require(try engine.perform(.convert("jpg"), on: [png]).first)
        #expect(jpg.lastPathComponent == "dot.jpg")
        #expect(pixelSize(jpg)?.0 == 40)

        let rotated = try #require(try engine.perform(.tool(.rotate), on: [png]).first)
        #expect(rotated.lastPathComponent == "dot rotated.png")
        #expect(pixelSize(rotated).map { [$0.0, $0.1] } == [20, 40])

        let half = try #require(try engine.perform(.tool(.halfSize), on: [png]).first)
        #expect(pixelSize(half).map { [$0.0, $0.1] } == [20, 10])

        let pdf = try #require(try engine.perform(.tool(.makePDF), on: [png, jpg]).first)
        #expect(PDFDocument(url: pdf)?.pageCount == 2)

        let again = try #require(try engine.perform(.convert("jpg"), on: [png]).first)
        #expect(again.lastPathComponent == "dot 2.jpg", "never overwrites")
    }

    @Test func pdfSplitMergeAndRender() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try makePNG(in: dir, name: "a.png"), b = try makePNG(in: dir, name: "b.png")
        let pdf = try #require(try engine.perform(.tool(.makePDF), on: [a, b]).first)

        let folder = try #require(try engine.perform(.convert("png"), on: [pdf]).first)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["Page 1.png", "Page 2.png"])

        let pages = try #require(try engine.perform(.tool(.splitPDF), on: [pdf]).first)
        let parts = try FileManager.default.contentsOfDirectory(at: pages, includingPropertiesForKeys: nil)
        #expect(parts.count == 2)

        let merged = try #require(try engine.perform(.tool(.mergePDF), on: parts + [pdf]).first)
        #expect(PDFDocument(url: merged)?.pageCount == 4)
    }

    @Test func documentConversions() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let txt = dir.appendingPathComponent("notes.txt")
        try String(repeating: "Lime converts documents locally.\n", count: 200).write(to: txt, atomically: true, encoding: .utf8)

        let docx = try #require(try engine.perform(.convert("docx"), on: [txt]).first)
        let back = try NSAttributedString(url: docx, options: [:], documentAttributes: nil)
        #expect(back.string.contains("converts documents locally"))

        let pdf = try #require(try engine.perform(.convert("pdf"), on: [docx]).first)
        let document = try #require(PDFDocument(url: pdf))
        #expect(document.pageCount > 1, "long text paginates")
        #expect(document.string?.contains("converts documents") == true)
    }

    @Test func archiveRoundTrip() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try makePNG(in: dir, name: "a.png"), b = try makePNG(in: dir, name: "b.png")
        let zip = try #require(try engine.perform(.tool(.zip), on: [a, b]).first)
        #expect(zip.lastPathComponent == "Archive.zip")

        let tgz = try #require(try engine.perform(.convert("tgz"), on: [zip]).first)
        #expect(tgz.lastPathComponent == "Archive.tar.gz")

        let folder = try #require(try engine.perform(.tool(.extractArchive), on: [tgz]).first)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["a.png", "b.png"])
    }

    @Test func audioWithoutFFmpeg() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = dir.appendingPathComponent("tone.wav")
        try writeTone(to: wav)
        let aiff = try #require(try engine.perform(.convert("aiff"), on: [wav]).first)
        let m4a = try #require(try engine.perform(.convert("m4a"), on: [aiff]).first)
        #expect(try AVAudioFile(forReading: m4a).length > 40_000)
    }

    func writeTone(to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for i in 0..<44_100 { buffer.floatChannelData![0][i] = sin(Float(i) * 0.06) * 0.4 }
        try file.write(from: buffer)
    }
}
