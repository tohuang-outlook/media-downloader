import Foundation

public struct SubtitlePreviewCue: Equatable {
    public let id: String
    public let index: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public let rawText: String
    public let sourceLines: [String]

    public static func from(_ cue: Cue) throws -> SubtitlePreviewCue {
        SubtitlePreviewCue(
            id: "cue-\(cue.index)",
            index: cue.index,
            startSeconds: try SubtitlePreviewTime.seconds(fromSRT: cue.start),
            endSeconds: try SubtitlePreviewTime.seconds(fromSRT: cue.end),
            rawText: cue.text,
            sourceLines: cue.text.components(separatedBy: "\n")
        )
    }
}

public enum SubtitlePreviewTime {
    public static func seconds(fromSRT value: String) throws -> Double {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 3 else {
            throw SubtitleError.commandFailed(1, "Invalid SRT time: \(value)")
        }

        let secondsParts = parts[2].split(separator: ".")
        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0
        let seconds = Double(secondsParts[0]) ?? 0
        let fractional = secondsParts.count > 1 ? Double("0.\(secondsParts[1])") ?? 0 : 0

        return (hours * 3600) + (minutes * 60) + seconds + fractional
    }
}

public enum SubtitlePreviewLineSplitter {
    public static func split(_ text: String, maxCharactersPerLine: Int) -> [String] {
        if text.contains("\n") {
            return text.components(separatedBy: "\n")
        }

        if text.count <= maxCharactersPerLine {
            return [text]
        }

        let words = text.split(separator: " ").map(String.init)
        var bestLeft = text
        var bestRight = ""
        var bestScore = Int.max
        var foundPreferredSplit = false

        for index in 1..<words.count {
            let left = words[0..<index].joined(separator: " ")
            let right = words[index...].joined(separator: " ")

            if left.count <= maxCharactersPerLine {
                let score = abs(left.count - right.count)
                if !foundPreferredSplit || score < bestScore {
                    foundPreferredSplit = true
                    bestScore = score
                    bestLeft = left
                    bestRight = right
                }
                continue
            }

            if foundPreferredSplit {
                continue
            }

            let overflowPenalty = max(0, left.count - maxCharactersPerLine)
                + max(0, right.count - maxCharactersPerLine)
            let balancePenalty = abs(left.count - right.count)
            let score = overflowPenalty * 100 + balancePenalty

            if score < bestScore {
                bestScore = score
                bestLeft = left
                bestRight = right
            }
        }

        return bestRight.isEmpty ? [text] : [bestLeft, bestRight]
    }
}
