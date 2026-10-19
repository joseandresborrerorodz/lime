import Foundation

public enum LimeError: LocalizedError, Equatable {
    case unsupported(String)
    case missingTool(String)
    case toolFailed(String, String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let what): return "Not supported: \(what)"
        case .missingTool(let name): return "\(name) is not installed. Install it with Homebrew: brew install \(name)"
        case .toolFailed(let name, let output):
            let detail = output.split(separator: "\n").last.map(String.init) ?? ""
            return "\(name) failed. \(detail)"
        case .failed(let message): return message
        }
    }
}

enum ProcessRunner {
    /// Runs an executable to completion and throws with its stderr on failure.
    static func run(_ executable: URL, _ arguments: [String], in directory: URL? = nil) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let output = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LimeError.toolFailed(
                executable.lastPathComponent,
                String(decoding: output, as: UTF8.self)
            )
        }
    }

    /// Runs an executable and returns its stdout, or nil if it fails.
    static func output(_ executable: URL, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    static func system(_ path: String) -> URL { URL(fileURLWithPath: path) }
}

/// Runs `body` on the main thread, synchronously, from any thread.
func onMain<T>(_ body: () throws -> T) rethrows -> T {
    if Thread.isMainThread { return try body() }
    return try DispatchQueue.main.sync(execute: body)
}

/// A fresh scratch directory; the caller removes it when done.
func makeScratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("lime-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
