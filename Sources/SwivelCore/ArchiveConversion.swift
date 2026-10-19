import Foundation

/// ZIP and TAR through the tools that ship with macOS (`ditto`, `tar`).
enum ArchiveConversion {
    static let ditto = ProcessRunner.system("/usr/bin/ditto")
    static let tar = ProcessRunner.system("/usr/bin/tar")

    static func extract(_ archive: URL, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        switch FileFormat.normalizedExtension(of: archive) {
        case "zip": try ProcessRunner.run(ditto, ["-x", "-k", archive.path, folder.path])
        case "tar", "tgz": try ProcessRunner.run(tar, ["-xf", archive.path, "-C", folder.path])
        default: throw SwivelError.unsupported("extracting \(archive.lastPathComponent)")
        }
    }

    static func extract(_ archive: URL) throws -> URL {
        let folder = OutputNaming.toolURL(for: archive, suffix: "", extension: nil)
        try extract(archive, into: folder)
        return folder
    }

    /// Re-packs an archive's contents in another archive format.
    static func convert(_ archive: URL, to target: String, output: URL) throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try extract(archive, into: scratch)
        let entries = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
            .filter { $0 != "__MACOSX" }
        try pack(entries, from: scratch, as: target, to: output)
    }

    static func pack(_ names: [String], from directory: URL, as target: String, to output: URL) throws {
        switch target {
        case "zip":
            if names.count == 1 {
                try ProcessRunner.run(ditto, ["-c", "-k", "--sequesterRsrc", "--keepParent",
                                              directory.appendingPathComponent(names[0]).path, output.path])
            } else {
                try ProcessRunner.run(ditto, ["-c", "-k", "--sequesterRsrc", directory.path, output.path])
            }
        case "tar": try ProcessRunner.run(tar, ["-cf", output.path, "-C", directory.path] + names)
        case "tgz": try ProcessRunner.run(tar, ["-czf", output.path, "-C", directory.path] + names)
        default: throw SwivelError.unsupported("creating \(target) archives")
        }
    }

    /// Zips files and folders. One item becomes `name.zip`; several become `Archive.zip`.
    static func zip(_ inputs: [URL]) throws -> URL {
        let parent = inputs[0].deletingLastPathComponent()
        if inputs.count == 1 {
            let output = OutputNaming.uniqueURL(in: parent, base: inputs[0].lastPathComponent, extension: "zip")
            try ProcessRunner.run(ditto, ["-c", "-k", "--sequesterRsrc", "--keepParent", inputs[0].path, output.path])
            return output
        }
        // ditto archives one source, so stage the selection as clones in a scratch folder.
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        for input in inputs {
            try FileManager.default.copyItem(at: input, to: scratch.appendingPathComponent(input.lastPathComponent))
        }
        let output = OutputNaming.uniqueURL(in: parent, base: "Archive", extension: "zip")
        try ProcessRunner.run(ditto, ["-c", "-k", "--sequesterRsrc", scratch.path, output.path])
        return output
    }
}
