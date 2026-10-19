import Foundation

/// Plain-text formats converted in Swift: subtitles and delimited tables.
public enum TextFormats {
    struct Cue {
        var start: String
        var end: String
        var lines: [String]
    }

    // MARK: Subtitles

    static let arrow = "-->"

    /// Parses SRT or WebVTT into cues. Cue identifiers, styles and notes are dropped.
    static func parseCues(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var cues: [Cue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains(arrow) }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: arrow)
            guard parts.count == 2 else { continue }
            let start = parts[0].trimmingCharacters(in: .whitespaces)
            // WebVTT allows cue settings after the end time ("00:01.000 align:start").
            let end = parts[1].trimmingCharacters(in: .whitespaces)
                .split(separator: " ").first.map(String.init) ?? ""
            cues.append(Cue(start: start, end: end, lines: Array(lines[(timingIndex + 1)...])))
        }
        return cues
    }

    /// Normalizes a timestamp to `HH:MM:SS<sep>mmm`.
    static func timestamp(_ value: String, separator: Character) -> String {
        let unified = value.replacingOccurrences(of: ",", with: ".")
        var pieces = unified.split(separator: ":").map(String.init)
        while pieces.count < 3 { pieces.insert("00", at: 0) }
        var seconds = pieces[2]
        if !seconds.contains(".") { seconds += ".000" }
        let secondParts = seconds.split(separator: ".")
        let whole = String(secondParts[0]).leftPadded(to: 2)
        let millis = String(String(secondParts.count > 1 ? secondParts[1] : "0").prefix(3)).rightPadded(to: 3)
        return "\(pieces[0].leftPadded(to: 2)):\(pieces[1].leftPadded(to: 2)):\(whole)\(separator)\(millis)"
    }

    public static func subtitles(_ text: String, to target: String) throws -> String {
        let cues = parseCues(text)
        guard !cues.isEmpty else { throw LimeError.failed("No subtitle cues were found.") }
        switch target {
        case "srt":
            return cues.enumerated().map { index, cue in
                "\(index + 1)\n\(timestamp(cue.start, separator: ",")) --> \(timestamp(cue.end, separator: ","))\n"
                    + cue.lines.joined(separator: "\n")
            }.joined(separator: "\n\n") + "\n"
        case "vtt":
            return "WEBVTT\n\n" + cues.map { cue in
                "\(timestamp(cue.start, separator: ".")) --> \(timestamp(cue.end, separator: "."))\n"
                    + cue.lines.joined(separator: "\n")
            }.joined(separator: "\n\n") + "\n"
        case "txt":
            let stripped = cues.flatMap(\.lines).map { line in
                line.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            }
            return stripped.joined(separator: "\n") + "\n"
        default:
            throw LimeError.unsupported("subtitles to \(target)")
        }
    }

    // MARK: Delimited tables

    /// RFC 4180 style CSV parsing: quoted fields, doubled quotes, embedded newlines.
    public static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        while let char = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else { quoted = false }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"" where field.isEmpty: quoted = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n", "\r":
                row.append(field); rows.append(row); row = []; field = ""
            default: field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    public static func table(_ text: String, from source: String, to target: String) throws -> String {
        let rows: [[String]]
        switch source {
        case "csv": rows = parseCSV(text)
        case "tsv":
            rows = text.replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
                .filter { !($0.count == 1 && $0[0].isEmpty) }
        default: throw LimeError.unsupported("reading \(source)")
        }
        switch target {
        case "tsv":
            return rows.map { row in
                row.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
                    .joined(separator: "\t")
            }.joined(separator: "\n") + "\n"
        case "csv":
            return rows.map { row in
                row.map { field in
                    field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                        ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                        : field
                }.joined(separator: ",")
            }.joined(separator: "\n") + "\n"
        default: throw LimeError.unsupported("writing \(target)")
        }
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }

    func rightPadded(to length: Int) -> String {
        count >= length ? self : self + String(repeating: "0", count: length - count)
    }
}
