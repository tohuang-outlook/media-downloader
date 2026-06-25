import Foundation

/// Writes bilingual ASS subtitle files from paired Chinese + English SRT cue arrays.
public struct ASSWriter {

    public init() {}

    public func write(
        zhCues: [Cue],
        enCues: [Cue],
        to output: URL,
        width: Int,
        height: Int
    ) throws {
        guard !zhCues.isEmpty else { throw SubtitleError.emptySRT("Chinese") }

        // ~2.8% of height gives ~30px at 1080p — standard broadcast size
        let fontSize  = max(22, Int(Double(height) * 0.028))
        let marginV   = max(30, Int(Double(height) * 0.045))
        let outline   = max(2,  Int(Double(height) * 0.002))

        var lines = [
            "[Script Info]",
            "ScriptType: v4.00+",
            "PlayResX: \(width)",
            "PlayResY: \(height)",
            "ScaledBorderAndShadow: yes",
            "",
            "[V4+ Styles]",
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, " +
            "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, " +
            "Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
            "Style: Default,Heiti SC,\(fontSize),&H00FFFFFF,&H000000FF,&H00000000,&H99000000," +
            "0,0,0,0,100,100,0,0,1,\(outline),1,2,80,80,\(marginV),1",
            "",
            "[Events]",
            "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
        ]

        for (i, zh) in zhCues.enumerated() {
            let enText = i < enCues.count ? enCues[i].text : ""
            let body = "\(ASSEscape.body(zh.text))\\N\(ASSEscape.body(enText))"
            lines.append(
                "Dialogue: 0,\(ASSTime.fromSRT(zh.start)),\(ASSTime.fromSRT(zh.end))," +
                "Default,,0,0,0,,\(body)"
            )
        }

        try lines.joined(separator: "\n")
            .appending("\n")
            .write(to: output, atomically: true, encoding: .utf8)
    }
}
