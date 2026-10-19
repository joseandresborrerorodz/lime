import Foundation
import Testing
@testable import LimeCore

@Suite struct FileFormatTests {
    @Test func normalizesAliasesAndDoubleExtensions() {
        #expect(FileFormat.normalizedExtension(of: URL(fileURLWithPath: "/a/Photo.JPEG")) == "jpg")
        #expect(FileFormat.normalizedExtension(of: URL(fileURLWithPath: "/a/logs.tar.gz")) == "tgz")
        #expect(FileFormat.baseName(of: URL(fileURLWithPath: "/a/logs.tar.gz")) == "logs")
        #expect(FileFormat.baseName(of: URL(fileURLWithPath: "/a/my.report.docx")) == "my.report")
    }
}

@Suite struct CatalogTests {
    let bare = Catalog(capabilities: .none)
    let full = Catalog(capabilities: Capabilities(
        ffmpeg: URL(fileURLWithPath: "/usr/bin/true"), cwebp: URL(fileURLWithPath: "/usr/bin/true")))

    func urls(_ names: String...) -> [URL] { names.map { URL(fileURLWithPath: "/tmp/\($0)") } }

    @Test func excludesTheInputFormat() {
        let targets = bare.conversions(for: urls("a.png"))
        #expect(!targets.contains("png"))
        #expect(targets.contains("jpg"))
        #expect(!targets.contains("webp"), "WebP needs cwebp")
        #expect(full.conversions(for: urls("a.png")).contains("webp"))
    }

    @Test func mixedImageFormatsShareTargets() {
        let targets = bare.conversions(for: urls("a.png", "b.jpg"))
        #expect(targets.contains("png") && targets.contains("jpg") && targets.contains("heic"))
    }

    @Test func mixedCategoriesHaveNoConversions() {
        #expect(bare.conversions(for: urls("a.png", "b.mp3")).isEmpty)
    }

    @Test func mediaDependsOnFFmpeg() {
        #expect(bare.conversions(for: urls("clip.mkv")).isEmpty)
        #expect(bare.conversions(for: urls("clip.mov")) == ["mp4", "m4v", "m4a"])
        #expect(full.conversions(for: urls("clip.mkv")).contains("webm"))
        #expect(full.conversions(for: urls("song.ogg")).contains("mp3"))
    }

    @Test func toolsDependOnSelection() {
        #expect(bare.tools(for: urls("a.jpg")) == [.compress, .stripMetadata, .halfSize, .rotate, .zip])
        #expect(bare.tools(for: urls("a.jpg", "b.png")).contains(.makePDF))
        #expect(bare.tools(for: urls("a.pdf", "b.pdf")) == [.mergePDF, .zip])
        #expect(bare.tools(for: urls("a.pdf", "b.mp3")) == [.zip])
        #expect(full.tools(for: urls("a.mp4")).contains(.videoToGIF))
    }
}

@Suite struct OutputNamingTests {
    @Test func countsUpPastExistingFiles() {
        let dir = URL(fileURLWithPath: "/tmp/x")
        let taken: Set<String> = ["/tmp/x/photo.png", "/tmp/x/photo 2.png"]
        let url = OutputNaming.uniqueURL(in: dir, base: "photo", extension: "png") { taken.contains($0.path) }
        #expect(url.lastPathComponent == "photo 3.png")
    }

    @Test func tarGzKeepsBothSuffixes() {
        let url = OutputNaming.conversionURL(for: URL(fileURLWithPath: "/nonexistent/backup.zip"), target: "tgz")
        #expect(url.lastPathComponent == "backup.tar.gz")
    }
}
