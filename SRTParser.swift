import Foundation

// MARK: - Models

public struct Cue: Equatable {
    public let index: Int
    public let start: String
    public let end: String
    public let text: String

    public init(index: Int, start: String, end: String, text: String) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
    }
}

// MARK: - SRTParser

public enum SRTParserError: LocalizedError {
    case emptyFile
    case malformedBlock(String)

    public var errorDescription: String? {
        switch self {
        case .emptyFile: return "SRT file is empty."
        case .malformedBlock(let b): return "Malformed SRT block: \(b)"
        }
    }
}

public struct SRTParser {

    public init() {}

    /// Parse an SRT file URL into an ordered array of Cues.
    public func parse(_ url: URL) throws -> [Cue] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return try parse(string: raw)
    }

    /// Parse raw SRT text into an ordered array of Cues.
    public func parse(string raw: String) throws -> [Cue] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [Cue] = []

        for block in blocks {
            let lines = block
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard lines.count >= 2 else { continue }

            // Find timing line — may be line 0 (no index) or line 1 (index present)
            let timingIndex = lines[0].contains("-->") ? 0 : 1
            guard lines.indices.contains(timingIndex),
                  lines[timingIndex].contains("-->") else { continue }

            let timing = lines[timingIndex].components(separatedBy: "-->")
            guard timing.count == 2 else { continue }

            let start = timing[0].trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ")[0]
            let end = timing[1].trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ")[0]
            let text = lines.dropFirst(timingIndex + 1).joined(separator: "\n")
            let index = Int(lines[0].trimmingCharacters(in: .whitespacesAndNewlines)) ?? (cues.count + 1)

            cues.append(Cue(index: index, start: start, end: end, text: text))
        }

        return cues
    }
}

// MARK: - Time conversion

public struct ASSTime {

    /// Convert SRT timestamp (00:01:23,456) → ASS timestamp (0:01:23.45)
    public static func fromSRT(_ value: String) -> String {
        let parts = value.replacingOccurrences(of: ",", with: ".").components(separatedBy: ".")
        let hms = parts[0].split(separator: ":").map(String.init)
        guard hms.count == 3 else { return "0:00:00.00" }
        let centis = String((parts.count > 1 ? parts[1] : "00").prefix(2))
        let h = Int(hms[0]) ?? 0
        return "\(h):\(hms[1]):\(hms[2]).\(centis)"
    }
}

// MARK: - ASS escaping

public struct ASSEscape {

    public static func body(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "\n", with: "\\N")
    }

    /// Escape a file path for use inside an ffmpeg filter string.
    public static func filterPath(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: ",", with: "\\,")
    }
}
