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
import Security

/// Stores and retrieves per-provider API keys from the macOS Keychain.
/// Keys are scoped to the app's bundle identifier so they survive app restarts.
public struct KeychainStore {

    private static let service = Bundle.main.bundleIdentifier ?? "com.subtitle-burner"

    // MARK: - Public API

    public static func save(key: String, for provider: String) {
        let account = accountName(for: provider)
        let data = Data(key.utf8)

        // Try update first
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet — add it
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    public static func load(for provider: String) -> String? {
        let account = accountName(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else { return nil }
        return string
    }

    public static func delete(for provider: String) {
        let account = accountName(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private

    private static func accountName(for provider: String) -> String {
        "api-key-\(provider.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }
}

/// Persists all user-configurable app settings via UserDefaults.
/// Call `save()` whenever a field changes; call the static properties on launch to restore.
public struct Settings {

    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key: String {
        case outputFolder
        case ffmpegPath
        case ffprobePath
        case whisperPath
        case whisperModel
        case translateProvider
        case translateModel
        case fontPath
        case lastSourceFolder
    }

    // MARK: - Properties

    public static var outputFolder: String {
        get { defaults.string(forKey: Key.outputFolder.rawValue) ?? "\(NSHomeDirectory())/Downloads" }
        set { defaults.set(newValue, forKey: Key.outputFolder.rawValue) }
    }

    public static var ffmpegPath: String {
        get { defaults.string(forKey: Key.ffmpegPath.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.ffmpegPath.rawValue) }
    }

    public static var ffprobePath: String {
        get { defaults.string(forKey: Key.ffprobePath.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.ffprobePath.rawValue) }
    }

    public static var whisperPath: String {
        get { defaults.string(forKey: Key.whisperPath.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.whisperPath.rawValue) }
    }

    public static var whisperModel: String {
        get { defaults.string(forKey: Key.whisperModel.rawValue) ?? "turbo" }
        set { defaults.set(newValue, forKey: Key.whisperModel.rawValue) }
    }

    public static var translateProvider: String {
        get { defaults.string(forKey: Key.translateProvider.rawValue) ?? "OpenAI" }
        set { defaults.set(newValue, forKey: Key.translateProvider.rawValue) }
    }

    public static var translateModel: String {
        get { defaults.string(forKey: Key.translateModel.rawValue) ?? "gpt-4.1-mini" }
        set { defaults.set(newValue, forKey: Key.translateModel.rawValue) }
    }

    /// Path to the CJK font used for subtitle burn-in.
    /// Falls back to the bundled Noto font path if the system STHeiti is absent.
    public static var fontPath: String {
        get {
            if let saved = defaults.string(forKey: Key.fontPath.rawValue), !saved.isEmpty {
                return saved
            }
            return preferredSystemFont()
        }
        set { defaults.set(newValue, forKey: Key.fontPath.rawValue) }
    }

    public static var lastSourceFolder: String {
        get { defaults.string(forKey: Key.lastSourceFolder.rawValue) ?? NSHomeDirectory() }
        set { defaults.set(newValue, forKey: Key.lastSourceFolder.rawValue) }
    }

    // MARK: - Font resolution

    /// Returns the best available CJK font path, preferring the system font,
    /// then a bundled fallback, then an empty string (caller should warn the user).
    public static func preferredSystemFont() -> String {
        let candidates = [
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/Library/Fonts/Arial Unicode MS.ttf",
            // Bundled fallback — place NotoSansCJKtc-Regular.otf in the app bundle
            Bundle.main.path(forResource: "NotoSansCJKtc-Regular", ofType: "otf") ?? ""
        ]
        return candidates.first { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) } ?? ""
    }

    /// Default model name for a given provider.
    public static func defaultModel(for provider: String) -> String {
        switch provider {
        case "DeepSeek":    return "deepseek-chat"
        case "Kimi 2.5":   return "moonshot-v1-8k"
        case "Google Gemini": return "gemini-2.5-flash"
        default:            return "gpt-4.1-mini"
        }
    }
}

// MARK: - Protocol

public protocol TranslationService {
    var providerName: String { get }
    func translate(cues: [Cue], model: String, apiKey: String) async throws -> [Cue]
}

// MARK: - Shared helpers

struct TranslationHelpers {

    static let maxChunkSize = 24

    /// Splits cues into chunks, translates each, retries on failure with halved chunk size.
    static func translateAll(
        cues: [Cue],
        model: String,
        apiKey: String,
        log: @escaping (String) -> Void,
        callAPI: @escaping ([Cue]) async throws -> [Int: String]
    ) async throws -> [Cue] {
        var translated = Array(repeating: "", count: cues.count)
        try await translateRange(cues, start: 0, end: cues.count,
                                 maxChunkSize: maxChunkSize, translated: &translated,
                                 log: log, callAPI: callAPI)
        return cues.enumerated().map { i, cue in
            Cue(index: cue.index, start: cue.start, end: cue.end, text: translated[i])
        }
    }

    private static func translateRange(
        _ cues: [Cue], start: Int, end: Int, maxChunkSize: Int,
        translated: inout [String],
        log: @escaping (String) -> Void,
        callAPI: @escaping ([Cue]) async throws -> [Int: String]
    ) async throws {
        var cursor = start
        while cursor < end {
            let chunkEnd = min(cursor + maxChunkSize, end)
            let chunk = Array(cues[cursor..<chunkEnd])
            log("Translating cues \(cursor + 1)–\(chunkEnd) of \(cues.count)…")
            do {
                let result = try await callAPI(chunk)
                for i in cursor..<chunkEnd {
                    guard let text = result[cues[i].index],
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw SubtitleError.translationMissingCue(cues[i].index)
                    }
                    translated[i] = text
                }
                cursor = chunkEnd
            } catch {
                let count = chunkEnd - cursor
                if count == 1 { throw error }
                let smaller = max(1, count / 2)
                log("Retrying cues \(cursor + 1)–\(chunkEnd) in smaller batches: \(error.localizedDescription)")
                try await translateRange(cues, start: cursor, end: chunkEnd,
                                         maxChunkSize: smaller, translated: &translated,
                                         log: log, callAPI: callAPI)
                cursor = chunkEnd
            }
        }
    }

    /// Build the JSON translation prompt.
    static func prompt(for cues: [Cue]) throws -> String {
        let items: [[String: Any]] = cues.map { ["id": $0.index, "text": $0.text] }
        let data = try JSONSerialization.data(withJSONObject: items)
        let json = String(data: data, encoding: .utf8) ?? "[]"
        return """
        Translate the `text` field of each object in this JSON array from English into Traditional Chinese.
        Keep subtitles natural and concise for burned-in video.
        Preserve every `id` exactly.
        Do not merge, omit, renumber, reorder, or add items.
        Return only a valid JSON array of objects shaped exactly like:
        [{"id": 1, "text": "翻譯"}]
        No Markdown, no code fences.

        \(json)
        """
    }

    /// Parse a JSON array of {id, text} objects into a dictionary.
    static func parseJSONResult(_ raw: String, expectedIDs: Set<Int>) throws -> [Int: String] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip optional markdown fences
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SubtitleError.badTranslationJSON(text)
        }
        var result: [Int: String] = [:]
        for obj in array {
            guard let id = obj["id"] as? Int, let t = obj["text"] as? String else {
                throw SubtitleError.missingIDOrText(String(describing: obj))
            }
            result[id] = t
        }
        let actual = Set(result.keys)
        guard actual == expectedIDs else {
            let missing = expectedIDs.subtracting(actual).sorted()
            let extra = actual.subtracting(expectedIDs).sorted()
            throw SubtitleError.translationIDMismatch(missing: missing, extra: extra)
        }
        return result
    }

    /// Perform an HTTP POST and return the response body as Data.
    static func post(url: URL, body: [String: Any], headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? "(no body)"
            throw SubtitleError.httpError(http.statusCode, detail)
        }
        return data
    }
}

// MARK: - Error type

public enum SubtitleError: LocalizedError {
    case missingSource
    case missingTool(String)
    case missingFile(String)
    case missingAPIKey(String)
    case translationMissingCue(Int)
    case badTranslationJSON(String)
    case missingIDOrText(String)
    case translationIDMismatch(missing: [Int], extra: [Int])
    case httpError(Int, String)
    case whisperOutputNotFound(String)
    case commandFailed(Int, String)
    case noFontFound
    case emptySRT(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingSource:            return "Choose a source video first."
        case .missingTool(let n):       return "\(n) not found. Install it and set its path."
        case .missingFile(let p):       return "File not found: \(p)"
        case .missingAPIKey(let p):     return "Enter a \(p) API key to auto-translate."
        case .translationMissingCue(let i): return "Translation missing cue \(i)."
        case .badTranslationJSON(let s): return "Translation was not valid JSON: \(s)"
        case .missingIDOrText(let s):   return "Translation item missing id/text: \(s)"
        case .translationIDMismatch(let m, let e):
            return "Translation ID mismatch. Missing: \(m), extra: \(e)."
        case .httpError(let code, let detail): return "HTTP \(code): \(detail)"
        case .whisperOutputNotFound(let p): return "Whisper did not create expected SRT: \(p)"
        case .commandFailed(let code, let cmd): return "Command exited \(code): \(cmd)"
        case .noFontFound:
            return "No CJK font found. Install a font or set a custom path in Settings."
        case .emptySRT(let label):      return "\(label) SRT has no cues."
        case .cancelled:                return "Job cancelled."
        }
    }
}

// MARK: - OpenAI provider

public struct OpenAITranslationService: TranslationService {
    public let providerName = "OpenAI"

    public init() {}

    public func translate(cues: [Cue], model: String, apiKey: String) async throws -> [Cue] {
        try await TranslationHelpers.translateAll(cues: cues, model: model, apiKey: apiKey,
                                                   log: { _ in }) { chunk in
            try await callAPI(chunk: chunk, model: model, apiKey: apiKey)
        }
    }

    func callAPI(chunk: [Cue], model: String, apiKey: String) async throws -> [Int: String] {
        let prompt = try TranslationHelpers.prompt(for: chunk)
        let body: [String: Any] = [
            "model": model,
            "instructions": "You are a professional subtitle translator. Return only valid JSON.",
            "input": prompt
        ]
        let data = try await TranslationHelpers.post(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            body: body,
            headers: ["Authorization": "Bearer \(apiKey)"]
        )
        let raw = try extractOpenAIText(from: data)
        let expectedIDs = Set(chunk.map(\.index))
        return try TranslationHelpers.parseJSONResult(raw, expectedIDs: expectedIDs)
    }

    private func extractOpenAIText(from data: Data) throws -> String {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let text = obj?["output_text"] as? String { return text }
        if let output = obj?["output"] as? [[String: Any]] {
            let parts = output.flatMap { item -> [String] in
                (item["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
            }
            if !parts.isEmpty { return parts.joined(separator: "\n") }
        }
        throw SubtitleError.badTranslationJSON(String(data: data, encoding: .utf8) ?? "")
    }
}

// MARK: - Chat Completions provider (DeepSeek / Kimi)

public struct ChatCompletionsService: TranslationService {
    public let providerName: String
    let baseURL: String

    public init(provider: String) {
        self.providerName = provider
        switch provider {
        case "DeepSeek": baseURL = "https://api.deepseek.com"
        case "Kimi 2.5": baseURL = "https://api.moonshot.ai/v1"
        default: baseURL = "https://api.openai.com/v1"
        }
    }

    public func translate(cues: [Cue], model: String, apiKey: String) async throws -> [Cue] {
        try await TranslationHelpers.translateAll(cues: cues, model: model, apiKey: apiKey,
                                                   log: { _ in }) { chunk in
            try await callAPI(chunk: chunk, model: model, apiKey: apiKey)
        }
    }

    func callAPI(chunk: [Cue], model: String, apiKey: String) async throws -> [Int: String] {
        let prompt = try TranslationHelpers.prompt(for: chunk)
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a professional subtitle translator. Return only valid JSON."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]
        let data = try await TranslationHelpers.post(
            url: URL(string: "\(baseURL)/chat/completions")!,
            body: body,
            headers: ["Authorization": "Bearer \(apiKey)"]
        )
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = (obj?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any],
              let text = content["content"] as? String else {
            throw SubtitleError.badTranslationJSON(String(data: data, encoding: .utf8) ?? "")
        }
        return try TranslationHelpers.parseJSONResult(text, expectedIDs: Set(chunk.map(\.index)))
    }
}

// MARK: - Gemini provider

public struct GeminiTranslationService: TranslationService {
    public let providerName = "Google Gemini"

    public init() {}

    public func translate(cues: [Cue], model: String, apiKey: String) async throws -> [Cue] {
        try await TranslationHelpers.translateAll(cues: cues, model: model, apiKey: apiKey,
                                                   log: { _ in }) { chunk in
            try await callAPI(chunk: chunk, model: model, apiKey: apiKey)
        }
    }

    func callAPI(chunk: [Cue], model: String, apiKey: String) async throws -> [Int: String] {
        let prompt = try TranslationHelpers.prompt(for: chunk)
        let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escaped):generateContent")!
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": "You are a professional subtitle translator. Return only valid JSON.\n\n\(prompt)"]]]],
            "generationConfig": ["temperature": 0.2, "thinkingConfig": ["thinkingBudget": 0]]
        ]
        let data = try await TranslationHelpers.post(url: url, body: body, headers: ["x-goog-api-key": apiKey])
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = ((obj?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
        let joined = text?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
        guard !joined.isEmpty else {
            throw SubtitleError.badTranslationJSON(String(data: data, encoding: .utf8) ?? "")
        }
        return try TranslationHelpers.parseJSONResult(joined, expectedIDs: Set(chunk.map(\.index)))
    }
}

// MARK: - Factory

public struct TranslationServiceFactory {
    public static func make(for provider: String) -> TranslationService {
        switch provider {
        case "OpenAI":        return OpenAITranslationService()
        case "DeepSeek":      return ChatCompletionsService(provider: "DeepSeek")
        case "Kimi 2.5":      return ChatCompletionsService(provider: "Kimi 2.5")
        case "Google Gemini": return GeminiTranslationService()
        default:              return OpenAITranslationService()
        }
    }
}

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

        // Two separate styles:
        // ZH: larger CJK font, sits above EN
        // EN: slightly smaller, sits at the very bottom
        let zhFontSize = max(18, Int(Double(height) * 0.026))  // Chinese — slightly larger
        let enFontSize = max(16, Int(Double(height) * 0.022))  // English — slightly smaller
        let marginV    = max(20, Int(Double(height) * 0.030))  // bottom margin for EN line
        let zhMarginV  = max(20, Int(Double(height) * 0.030)) + enFontSize + max(10, Int(Double(height) * 0.018))
        let marginH    = max(20, Int(Double(width)  * 0.04))
        let outline    = max(1,  Int(Double(height) * 0.0015))
        let styleRow   = "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, " +
                         "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, " +
                         "Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding"

        var lines = [
            "[Script Info]",
            "ScriptType: v4.00+",
            "PlayResX: \(width)",
            "PlayResY: \(height)",
            "ScaledBorderAndShadow: yes",
            "WrapStyle: 0",
            "",
            "[V4+ Styles]",
            styleRow,
            // EN style: bottom position, smaller font
            "Style: EN,Arial,\(enFontSize),&H00FFFFFF,&H000000FF,&H00000000,&H88000000," +
            "0,0,0,0,100,100,0,0,1,\(outline),1,2,\(marginH),\(marginH),\(marginV),1",
            // ZH style: above EN, larger CJK font
            "Style: ZH,Heiti SC,\(zhFontSize),&H00FFFFFF,&H000000FF,&H00000000,&H88000000," +
            "0,0,0,0,100,100,0,0,1,\(outline),1,2,\(marginH),\(marginH),\(zhMarginV),1",
            "",
            "[Events]",
            "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
        ]

        // Each cue = two dialogue lines: one EN (bottom), one ZH (above EN)
        for (i, zh) in zhCues.enumerated() {
            let enText = i < enCues.count ? enCues[i].text : ""
            let start  = ASSTime.fromSRT(zh.start)
            let end    = ASSTime.fromSRT(zh.end)
            // EN line at bottom
            if !enText.isEmpty {
                lines.append(
                    "Dialogue: 0,\(start),\(end),EN,,0,0,0,,\(ASSEscape.body(enText))"
                )
            }
            // ZH line above EN
            lines.append(
                "Dialogue: 1,\(start),\(end),ZH,,0,0,0,,\(ASSEscape.body(zh.text))"
            )
        }

        try lines.joined(separator: "\n")
            .appending("\n")
            .write(to: output, atomically: true, encoding: .utf8)
    }
}
import AppKit
import UniformTypeIdentifiers

// MARK: - Job item (for batch processing)

public struct BatchJob: Identifiable, Equatable {
    public enum Status: Equatable {
        case queued
        case running(step: String)
        case done
        case failed(String)
        case cancelled
    }

    public let id: UUID
    public let sourceURL: URL
    public var status: Status

    public init(sourceURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.status = .queued
    }

    public var displayName: String { sourceURL.lastPathComponent }
}

// MARK: - Paths

public struct Paths {
    public let root: URL
    public let mp4: URL
    public let wav: URL
    public let zhSRT: URL
    public let enSRT: URL
    public let ass: URL
    public let burned: URL

    public init(source: URL, outputRoot: URL) {
        let stem = source.deletingPathExtension().lastPathComponent
        root    = outputRoot.appendingPathComponent("\(stem)_subtitle_work", isDirectory: true)
        mp4     = root.appendingPathComponent("\(stem).mp4")
        wav     = root.appendingPathComponent("\(stem).wav")
        zhSRT   = root.appendingPathComponent("\(stem).zh.srt")
        enSRT   = root.appendingPathComponent("\(stem).en.srt")
        ass     = root.appendingPathComponent("\(stem).zh_en.ass")
        burned  = root.appendingPathComponent("\(stem)_with_subtitles.mp4")
    }
}

// MARK: - Progress

public struct PipelineProgress: Sendable {
    public let step: String          // human-readable label
    public let fraction: Double      // 0…1 within current job
    public let ffmpegTime: String?   // parsed from ffmpeg stderr e.g. "00:01:23"

    public init(step: String, fraction: Double, ffmpegTime: String? = nil) {
        self.step = step
        self.fraction = fraction
        self.ffmpegTime = ffmpegTime
    }
}

public struct SubtitlePreviewClipJob: Equatable {
    public let startSeconds: Double
    public let durationSeconds: Double
    public let outputURL: URL
}

extension PipelineRunner {
    nonisolated public static func makePreviewClipJob(paths: Paths, cue: SubtitlePreviewCue) -> SubtitlePreviewClipJob {
        let paddedStart = max(0, cue.startSeconds - 2.0)
        let paddedEnd = cue.endSeconds + 2.0
        let startMs = Int((paddedStart * 1000).rounded())
        let endMs = Int((paddedEnd * 1000).rounded())
        let outputURL = paths.root.appendingPathComponent("preview_\(startMs)_\(endMs).mp4")
        return SubtitlePreviewClipJob(
            startSeconds: paddedStart,
            durationSeconds: paddedEnd - paddedStart,
            outputURL: outputURL
        )
    }

    nonisolated static func previewRenderSourceURL(source: URL, paths: Paths) -> URL {
        if FileManager.default.fileExists(atPath: paths.mp4.path) {
            return paths.mp4
        }
        return source
    }

    nonisolated static func makePreviewASSCues(from cues: [Cue], clipJob: SubtitlePreviewClipJob) throws -> [Cue] {
        let clipStart = clipJob.startSeconds
        let clipEnd = clipJob.startSeconds + clipJob.durationSeconds

        return try cues.compactMap { cue in
            let cueStart = try SubtitlePreviewTime.seconds(fromSRT: cue.start)
            let cueEnd = try SubtitlePreviewTime.seconds(fromSRT: cue.end)
            let overlapStart = max(cueStart, clipStart)
            let overlapEnd = min(cueEnd, clipEnd)

            guard overlapEnd > overlapStart else {
                return nil
            }

            let localStart = overlapStart - clipStart
            let localEnd = overlapEnd - clipStart

            return Cue(
                index: cue.index,
                start: Self.srtTimestamp(fromSeconds: localStart),
                end: Self.srtTimestamp(fromSeconds: localEnd),
                text: cue.text
            )
        }
    }
}

// MARK: - Runner

public final class PipelineRunner: ObservableObject {

    // Callbacks set by AppDelegate / UI
    public var onLog: @Sendable (String) -> Void = { _ in }
    public var onProgress: @Sendable (PipelineProgress) -> Void = { _ in }

    private var cancellationToken = CancellationToken()
    private var activeProcess: Process?

    // Tool paths (populated by AppDelegate from Settings + UI fields)
    public nonisolated(unsafe) var ffmpegPath: String  = ""
    public nonisolated(unsafe) var ffprobePath: String = ""
    public nonisolated(unsafe) var whisperPath: String = ""
    public nonisolated(unsafe) var fontPath: String    = ""
    public nonisolated(unsafe) var syncOffsetSeconds: Double = 0.0  // shift subtitles by N seconds

    public init() {}

    // MARK: - Cancellation

    public nonisolated func cancel() {
        cancellationToken.cancel()
        activeProcess?.terminate()
    }

    private func resetCancellation() {
        cancellationToken = CancellationToken()
    }

    // MARK: - Public pipeline steps

    public func runEnglishSRT(source: URL, outputFolder: URL, whisperModel: String) async throws -> URL {
        resetCancellation()
        let paths = Paths(source: source, outputRoot: outputFolder)
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)

        progress("Converting to H.264 MP4…", 0.05)
        try checkCancelled()
        try await run([ffmpegPath, "-y", "-i", source.path,
                       "-c:v", "libx264", "-preset", "fast", "-crf", "22",
                       "-c:a", "aac", "-b:a", "160k", paths.mp4.path])

        progress("Extracting audio WAV…", 0.2)
        try checkCancelled()
        // Extract WAV directly from original source to avoid any drift from double-conversion
        try await run([ffmpegPath, "-y", "-i", source.path,
                       "-vn", "-acodec", "pcm_s16le", "-ar", "16000",
                       "-ac", "1",          // mono — Whisper works better with mono
                       paths.wav.path])

        progress("Running Whisper transcription…", 0.35)
        try checkCancelled()
        try await run([whisperPath, paths.wav.path,
                       "--model", whisperModel,
                       "--language", "en",
                       "--task", "transcribe",
                       "--output_format", "srt",
                       "--output_dir", paths.root.path,
                       "--word_timestamps", "True",
                       "--max_line_count", "1",
                       "--max_line_width", "50",
                       "--condition_on_previous_text", "False",
                       "--no_speech_threshold", "0.6",
                       "--compression_ratio_threshold", "2.4"])

        // Whisper names output after the wav stem
        let wavStem = paths.wav.deletingPathExtension().lastPathComponent
        let whisperSRT = paths.root.appendingPathComponent("\(wavStem).srt")
        guard FileManager.default.fileExists(atPath: whisperSRT.path) else {
            throw SubtitleError.whisperOutputNotFound(whisperSRT.path)
        }
        if whisperSRT.path != paths.enSRT.path {
            if FileManager.default.fileExists(atPath: paths.enSRT.path) {
                try FileManager.default.removeItem(at: paths.enSRT)
            }
            try FileManager.default.moveItem(at: whisperSRT, to: paths.enSRT)
        }
        // Post-process: split long multi-sentence cues for better readability
        do {
            let parser = SRTParser()
            let rawCues = try parser.parse(paths.enSRT)
            let splitCues = splitLongCues(rawCues)
            if splitCues.count > rawCues.count {
                var lines: [String] = []
                for cue in splitCues {
                    lines.append("\(cue.index)")
                    lines.append("\(cue.start) --> \(cue.end)")
                    lines.append(cue.text)
                    lines.append("")
                }
                try lines.joined(separator: "\n")
                    .write(to: paths.enSRT, atomically: true, encoding: .utf8)
                log("Split \(rawCues.count) cues → \(splitCues.count) cues for better sync")
            }
        } catch { log("SRT split skipped: \(error.localizedDescription)") }

        // Apply sync offset if set
        if abs(syncOffsetSeconds) > 0.01 {
            do {
                let parser = SRTParser()
                let cues = try parser.parse(paths.enSRT)
                let shifted = cues.map { cue -> Cue in
                    let s = shiftSRTTime(cue.start, by: syncOffsetSeconds)
                    let e = shiftSRTTime(cue.end,   by: syncOffsetSeconds)
                    return Cue(index: cue.index, start: s, end: e, text: cue.text)
                }.filter { srtTimeToSeconds($0.start) >= 0 }
                var lines: [String] = []
                for cue in shifted {
                    lines.append("\(cue.index)")
                    lines.append("\(cue.start) --> \(cue.end)")
                    lines.append(cue.text); lines.append("")
                }
                try lines.joined(separator: "\n")
                    .write(to: paths.enSRT, atomically: true, encoding: .utf8)
                log("Applied sync offset: \(syncOffsetSeconds > 0 ? "+" : "")\(String(format: "%.2f", syncOffsetSeconds))s")
            } catch { log("Sync offset skipped: \(error.localizedDescription)") }
        }

        progress("English SRT ready.", 1.0)
        log("English SRT: \(paths.enSRT.path)")
        return paths.enSRT
    }

    public func translateSRT(
        enSRT: URL,
        zhSRT: URL,
        provider: String,
        model: String,
        apiKey: String
    ) async throws -> URL {
        resetCancellation()
        let parser = SRTParser()
        let cues = try parser.parse(enSRT)
        guard !cues.isEmpty else { throw SubtitleError.emptySRT("English") }

        progress("Translating with \(provider)…", 0.1)
        let service = TranslationServiceFactory.make(for: provider)

        // Inject logging
        var translated: [Cue] = []
        let total = cues.count
        var done = 0
        let chunk = 24
        var cursor = 0
        while cursor < total {
            try checkCancelled()
            let end = min(cursor + chunk, total)
            let slice = Array(cues[cursor..<end])
            let result = try await service.translate(cues: slice, model: model, apiKey: apiKey)
            translated.append(contentsOf: result)
            done += result.count
            progress("Translated \(done)/\(total) cues…", Double(done) / Double(total))
            cursor = end
        }

        // Write Chinese SRT
        var lines: [String] = []
        for (i, cue) in cues.enumerated() {
            lines.append("\(i + 1)")
            lines.append("\(cue.start) --> \(cue.end)")
            lines.append(i < translated.count ? translated[i].text : "")
            lines.append("")
        }
        try lines.joined(separator: "\n").write(to: zhSRT, atomically: true, encoding: .utf8)
        progress("Chinese SRT ready.", 1.0)
        log("Chinese SRT: \(zhSRT.path)")
        return zhSRT
    }

    public func mergeAndBurn(
        source: URL,
        outputFolder: URL,
        enSRTOverride: String,
        zhSRTOverride: String
    ) async throws -> URL {
        resetCancellation()
        let paths = Paths(source: source, outputRoot: outputFolder)
        let enPath = enSRTOverride.isEmpty ? paths.enSRT.path : enSRTOverride
        let zhPath = zhSRTOverride.isEmpty ? paths.zhSRT.path : zhSRTOverride

        guard FileManager.default.fileExists(atPath: paths.mp4.path) else {
            throw SubtitleError.missingFile(paths.mp4.path)
        }
        guard FileManager.default.fileExists(atPath: zhPath) else {
            throw SubtitleError.missingFile(zhPath)
        }
        guard FileManager.default.fileExists(atPath: enPath) else {
            throw SubtitleError.missingFile(enPath)
        }
        guard !fontPath.isEmpty, FileManager.default.fileExists(atPath: fontPath) else {
            throw SubtitleError.noFontFound
        }

        progress("Reading video resolution…", 0.05)
        let size = videoSize(paths.mp4)
        log("Video resolution: \(Int(size.width))×\(Int(size.height))")

        progress("Writing ASS subtitles…", 0.1)
        try checkCancelled()
        let parser = SRTParser()
        let zhCues = try parser.parse(URL(fileURLWithPath: zhPath))
        let enCues = try parser.parse(URL(fileURLWithPath: enPath))
        let writer = ASSWriter()
        try writer.write(zhCues: zhCues, enCues: enCues, to: paths.ass,
                         width: Int(size.width), height: Int(size.height))
        log("ASS: \(paths.ass.path)")

        progress("Burning subtitles into video…", 0.15)
        try checkCancelled()
        let fontDir = URL(fileURLWithPath: fontPath).deletingLastPathComponent().path
        let filter = "ass='\(ASSEscape.filterPath(paths.ass.path))':fontsdir='\(ASSEscape.filterPath(fontDir))'"
        try await run([ffmpegPath, "-y",
                       "-loglevel", "error",      // only show real errors, suppress libass font warnings
                       "-hide_banner",
                       "-i", paths.mp4.path,
                       "-vf", filter,
                       "-c:v", "libx264", "-preset", "fast", "-crf", "22",
                       "-c:a", "aac", "-b:a", "160k",
                       "-stats",                  // still show encoding progress
                       paths.burned.path])
        progress("Done!", 1.0)
        log("Burned video: \(paths.burned.path)")
        return paths.burned
    }

    public func runAll(
        source: URL,
        outputFolder: URL,
        whisperModel: String,
        provider: String,
        translateModel: String,
        apiKey: String,
        enSRTOverride: String,
        zhSRTOverride: String
    ) async throws -> URL {
        let paths = Paths(source: source, outputRoot: outputFolder)
        let enSRT = try await runEnglishSRT(source: source, outputFolder: outputFolder, whisperModel: whisperModel)
        let zhSRT = try await translateSRT(enSRT: enSRT, zhSRT: paths.zhSRT,
                                            provider: provider, model: translateModel, apiKey: apiKey)
        return try await mergeAndBurn(source: source, outputFolder: outputFolder,
                                       enSRTOverride: enSRT.path, zhSRTOverride: zhSRT.path)
    }

    public func renderPreviewClip(
        source: URL,
        outputFolder: URL,
        cue: SubtitlePreviewCue,
        enSRTOverride: String,
        zhSRTOverride: String
    ) async throws -> URL {
        resetCancellation()
        let paths = Paths(source: source, outputRoot: outputFolder)
        let clipJob = Self.makePreviewClipJob(paths: paths, cue: cue)
        let previewSourceURL = Self.previewRenderSourceURL(source: source, paths: paths)

        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: previewSourceURL.path) else {
            throw SubtitleError.missingFile(previewSourceURL.path)
        }

        if previewSourceURL == paths.mp4 {
            log("Preview source: normalized MP4 \(paths.mp4.path)")
        } else {
            log("Preview source fallback: original media \(source.path) (normalized MP4 missing at \(paths.mp4.path))")
        }

        let assURL = try writePreviewASSFile(
            videoURL: previewSourceURL,
            paths: paths,
            clipJob: clipJob,
            enSRTOverride: enSRTOverride,
            zhSRTOverride: zhSRTOverride
        )

        progress("Rendering preview clip…", 0.15)
        try checkCancelled()
        let filter = try makeASSFilter(for: assURL)
        try await run([ffmpegPath, "-y",
                       "-ss", Self.formatFFmpegSeconds(clipJob.startSeconds),
                       "-t", Self.formatFFmpegSeconds(clipJob.durationSeconds),
                       "-i", previewSourceURL.path,
                       "-vf", filter,
                       "-c:v", "libx264", "-preset", "fast", "-crf", "22",
                       "-c:a", "aac", "-b:a", "160k",
                       clipJob.outputURL.path])
        progress("Preview clip ready.", 1.0)
        log("Preview clip: \(clipJob.outputURL.path)")
        return clipJob.outputURL
    }

    // MARK: - Process execution

    private func run(_ args: [String]) async throws {
        try checkCancelled()
        log("$ \(args.joined(separator: " "))")
        guard FileManager.default.fileExists(atPath: args[0]) else {
            throw SubtitleError.missingTool(args[0])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline) {
                let s = String(line)
                self?.log(s)
                // Parse ffmpeg progress
                if let time = PipelineRunner.parseFFmpegTime(s) {
                    let cb = self?.onProgress
                    DispatchQueue.main.async {
                        cb?(PipelineProgress(step: "Encoding…", fraction: -1, ffmpegTime: time))
                    }
                }
            }
        }

        activeProcess = process
        try process.run()

        // Await completion without blocking the Swift concurrency thread
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }
        handle.readabilityHandler = nil
        activeProcess = nil

        if process.terminationStatus != 0 {
            throw SubtitleError.commandFailed(Int(process.terminationStatus), args[0])
        }
    }

    private func videoSize(_ url: URL) -> CGSize {
        guard FileManager.default.fileExists(atPath: ffprobePath) else {
            return CGSize(width: 1920, height: 1080)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = ["-v", "error", "-select_streams", "v:0",
                             "-show_entries", "stream=width,height", "-of", "json", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let streams = obj["streams"] as? [[String: Any]],
           let first = streams.first,
           let w = first["width"] as? Int, let h = first["height"] as? Int {
            return CGSize(width: w, height: h)
        }
        return CGSize(width: 1920, height: 1080)
    }

    private func checkCancelled() throws {
        if cancellationToken.isCancelled { throw SubtitleError.cancelled }
    }

    private func progress(_ step: String, _ fraction: Double) {
        log(step)
        onProgress(PipelineProgress(step: step, fraction: fraction))
    }

    private nonisolated func log(_ msg: String) {
        let cb = onLog
        DispatchQueue.main.async { cb(msg) }
    }

    private nonisolated static func parseFFmpegTime(_ line: String) -> String? {
        guard line.contains("time=") else { return nil }
        let parts = line.components(separatedBy: "time=")
        guard parts.count > 1 else { return nil }
        let time = parts[1].components(separatedBy: " ")[0]
        return time.hasPrefix("-") ? nil : time
    }

    private func writePreviewASSFile(
        videoURL: URL,
        paths: Paths,
        clipJob: SubtitlePreviewClipJob,
        enSRTOverride: String,
        zhSRTOverride: String
    ) throws -> URL {
        let subtitleURLs = try resolveSubtitleURLs(
            paths: paths,
            enSRTOverride: enSRTOverride,
            zhSRTOverride: zhSRTOverride
        )
        let _ = try validatedFontPath()
        let assURL = clipJob.outputURL.deletingPathExtension().appendingPathExtension("ass")

        progress("Reading video resolution…", 0.05)
        let size = videoSize(videoURL)
        log("Video resolution: \(Int(size.width))×\(Int(size.height))")

        progress("Writing ASS subtitles…", 0.1)
        try checkCancelled()
        let parser = SRTParser()
        let zhCues = try Self.makePreviewASSCues(from: parser.parse(subtitleURLs.zh), clipJob: clipJob)
        let enCues = try Self.makePreviewASSCues(from: parser.parse(subtitleURLs.en), clipJob: clipJob)
        let writer = ASSWriter()
        try writer.write(
            zhCues: zhCues,
            enCues: enCues,
            to: assURL,
            width: Int(size.width),
            height: Int(size.height)
        )
        log("ASS: \(assURL.path)")
        return assURL
    }

    private func resolveSubtitleURLs(
        paths: Paths,
        enSRTOverride: String,
        zhSRTOverride: String
    ) throws -> (en: URL, zh: URL) {
        let enPath = enSRTOverride.isEmpty ? paths.enSRT.path : enSRTOverride
        let zhPath = zhSRTOverride.isEmpty ? paths.zhSRT.path : zhSRTOverride

        guard FileManager.default.fileExists(atPath: zhPath) else {
            throw SubtitleError.missingFile(zhPath)
        }
        guard FileManager.default.fileExists(atPath: enPath) else {
            throw SubtitleError.missingFile(enPath)
        }

        return (
            en: URL(fileURLWithPath: enPath),
            zh: URL(fileURLWithPath: zhPath)
        )
    }

    private func validatedFontPath() throws -> String {
        guard !fontPath.isEmpty, FileManager.default.fileExists(atPath: fontPath) else {
            throw SubtitleError.noFontFound
        }
        return fontPath
    }

    private func makeASSFilter(for assURL: URL) throws -> String {
        let fontDir = URL(fileURLWithPath: try validatedFontPath()).deletingLastPathComponent().path
        return "ass='\(ASSEscape.filterPath(assURL.path))':fontsdir='\(ASSEscape.filterPath(fontDir))'"
    }

    private nonisolated static func srtTimestamp(fromSeconds value: Double) -> String {
        let totalMilliseconds = Int((value * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    private nonisolated static func formatFFmpegSeconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}


    // MARK: - SRT post-processing: split long cues at sentence boundaries

    /// Splits cues that contain multiple sentences into separate cues.
    /// e.g. "A. B. C." → three cues with proportionally divided timing.
    private func splitLongCues(_ cues: [Cue]) -> [Cue] {
        var result: [Cue] = []
        var newIndex = 1
        for cue in cues {
            // Split on sentence-ending punctuation followed by space
            let parts = splitAtSentences(cue.text)
            if parts.count <= 1 {
                result.append(Cue(index: newIndex, start: cue.start, end: cue.end, text: cue.text))
                newIndex += 1
                continue
            }
            // Divide the cue duration proportionally by character count
            let totalChars = max(1, parts.map(\.count).reduce(0, +))
            let startSecs = srtTimeToSeconds(cue.start)
            let endSecs   = srtTimeToSeconds(cue.end)
            let duration  = endSecs - startSecs
            var cursor = startSecs
            for part in parts {
                let fraction = Double(part.count) / Double(totalChars)
                let partDur  = max(0.5, duration * fraction)
                let partEnd  = min(cursor + partDur, endSecs)
                result.append(Cue(index: newIndex,
                                  start: secondsToSRTTime(cursor),
                                  end:   secondsToSRTTime(partEnd),
                                  text:  part.trimmingCharacters(in: .whitespaces)))
                cursor = partEnd
                newIndex += 1
            }
        }
        return result
    }

    private func splitAtSentences(_ text: String) -> [String] {
        // Split on ". ", "? ", "! ", "。", "？", "！" but keep short cues intact
        guard text.count > 50 else { return [text] }
        var parts: [String] = []
        var current = ""
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            current.append(ch)
            let next = text.index(after: i)
            let isEndPunct = ".?!。？！".contains(ch)
            let nextIsSpace = next < text.endIndex && (text[next] == " " || text[next] == "\n")
            if isEndPunct && (nextIsSpace || next == text.endIndex) && current.count > 15 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                // skip the space
                if nextIsSpace { i = text.index(after: next); continue }
            }
            i = next
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current.trimmingCharacters(in: .whitespaces))
        }
        return parts.filter { !$0.isEmpty }
    }

    private func srtTimeToSeconds(_ t: String) -> Double {
        // "00:01:23,456" → seconds
        let clean = t.replacingOccurrences(of: ",", with: ".")
        let parts = clean.components(separatedBy: ":")
        guard parts.count == 3 else { return 0 }
        let h = Double(parts[0]) ?? 0
        let m = Double(parts[1]) ?? 0
        let s = Double(parts[2]) ?? 0
        return h * 3600 + m * 60 + s
    }

    private func secondsToSRTTime(_ t: Double) -> String {
        let h   = Int(t / 3600)
        let m   = Int((t.truncatingRemainder(dividingBy: 3600)) / 60)
        let s   = Int(t.truncatingRemainder(dividingBy: 60))
        let ms  = Int((t - Double(Int(t))) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    private func shiftSRTTime(_ time: String, by offset: Double) -> String {
        let secs = srtTimeToSeconds(time) + offset
        let clamped = max(0, secs)
        return secondsToSRTTime(clamped)
    }

// MARK: - Cancellation token

final class CancellationToken: @unchecked Sendable {
    private(set) var isCancelled = false
    private let lock = NSLock()

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        isCancelled = true
    }
}
// SubtitleBurnerApp.swift
// Refactored: modular pipeline, async/await, Keychain, UserDefaults,
// progress bar, cancel, drag-and-drop, batch processing, font picker.


// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    // MARK: UI fields
    let sourceField          = NSTextField()
    let outputField          = NSTextField()
    let englishField         = NSTextField()
    let chineseField         = NSTextField()
    let ffmpegField          = NSTextField()
    let ffprobeField         = NSTextField()
    let whisperField         = NSTextField()
    let apiKeyField          = NSSecureTextField()
    let translateModelField  = NSTextField()
    let fontField            = NSTextField()
    let modelPopup           = NSPopUpButton()
    let providerPopup        = NSPopUpButton()
    let progressBar          = NSProgressIndicator()
    let progressLabel        = NSTextField(labelWithString: "")
    let syncOffsetField      = NSTextField()   // e.g. "-0.5" to shift back 0.5s
    let cancelButton         = NSButton()
    let logView              = NSTextView()
    let advancedStack        = NSStackView()
    let advancedChevron      = NSTextField(labelWithString: "›")
    let workflowCurrentLabel = NSTextField(labelWithString: "Choose a source video to get started.")
    let workflowNextLabel    = NSTextField(labelWithString: "Next: pick a .mov or .mp4 file.")
    let latestOutputTitleLabel = NSTextField(labelWithString: "No output yet")
    let latestOutputPathLabel  = NSTextField(labelWithString: "Run a step to generate subtitles or a burned video.")
    let openLatestOutputButton = NSButton()
    let revealLatestOutputButton = NSButton()
    let previewSubtitlesButton = NSButton()
    let editEnglishButton     = NSButton()
    let editChineseButton     = NSButton()
    let revealWorkFolderButton = NSButton()
    var advancedExpanded     = false
    var lastOutputURL: URL?
    var latestSourceVideoURL: URL?
    var latestEnglishSRTURL: URL?
    var latestChineseSRTURL: URL?
    var latestPreviewWindowController: SubtitlePreviewWindowController?

    // Batch table
    let batchTableView       = NSTableView()
    var batchJobs: [BatchJob] = []
    var batchScrollView: NSScrollView!

    // Runner
    let runner = PipelineRunner()
    var currentTask: Task<Void, Never>?

    struct PreviewLaunchAssets {
        let sourceURL: URL
        let outputFolderURL: URL
        let previewMediaURL: URL
        let englishSRTURL: URL
        let chineseSRTURL: URL?
        let cueSourceURL: URL
        let cueSourceLabel: String
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildUI()
        restoreSettings()
        updateWorkflowUI()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Settings persistence

    func restoreSettings() {
        sourceField.stringValue         = ""
        outputField.stringValue         = Settings.outputFolder
        ffmpegField.stringValue         = Settings.ffmpegPath.isEmpty   ? findTool("ffmpeg")   : Settings.ffmpegPath
        ffprobeField.stringValue        = Settings.ffprobePath.isEmpty  ? findTool("ffprobe")  : Settings.ffprobePath
        whisperField.stringValue        = Settings.whisperPath.isEmpty  ? findTool("whisper")  : Settings.whisperPath
        fontField.stringValue           = Settings.fontPath
        translateModelField.stringValue = Settings.translateModel

        // Restore popup selections
        let providers = ["OpenAI", "DeepSeek", "Kimi 2.5", "Google Gemini"]
        if let idx = providers.firstIndex(of: Settings.translateProvider) {
            providerPopup.selectItem(at: idx)
        }
        let models = ["turbo", "small", "medium", "large-v3"]
        if let idx = models.firstIndex(of: Settings.whisperModel) {
            modelPopup.selectItem(at: idx)
        }

        // Load API key from Keychain
        apiKeyField.stringValue = KeychainStore.load(for: selectedProvider()) ?? ""
        updateWorkflowUI()
    }

    func saveSettings() {
        Settings.outputFolder      = outputField.stringValue
        Settings.ffmpegPath        = ffmpegField.stringValue
        Settings.ffprobePath       = ffprobeField.stringValue
        Settings.whisperPath       = whisperField.stringValue
        Settings.translateProvider = selectedProvider()
        Settings.translateModel    = translateModelField.stringValue
        Settings.whisperModel      = selectedModel()
        Settings.fontPath          = fontField.stringValue

        // Persist API key to Keychain
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            KeychainStore.delete(for: selectedProvider())
        } else {
            KeychainStore.save(key: key, for: selectedProvider())
        }
    }

    // MARK: - UI Construction

    func buildUI() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "SubtitleBurner"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.08, green: 0.06, blue: 0.13, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.minSize = NSSize(width: 900, height: 640)
        window.contentView?.registerForDraggedTypes([.fileURL])

        let cv = window.contentView!
        cv.wantsLayer = true
        cv.layer?.backgroundColor = NSColor(red: 0.08, green: 0.06, blue: 0.13, alpha: 1).cgColor

        // ── Title bar ────────────────────────────────────────────────
        let titleBar = NSView()
        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = NSColor(red: 0.10, green: 0.08, blue: 0.16, alpha: 1).cgColor
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(titleBar)

        let appIconLabel = mkLabel("⬛", 18, .regular, NSColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 1))
        let appTitleLabel = mkLabel("SubtitleBurner", 17, .bold, .white)
        let appSubLabel   = mkLabel("Pro Workspace", 13, .regular, NSColor(white: 1, alpha: 0.45))
        let titleLeft = hstack([appIconLabel, appTitleLabel, appSubLabel], spacing: 8)

        // Status indicator
        let statusDotField = NSTextField(labelWithString: "●")
        statusDotField.font = .systemFont(ofSize: 10)
        statusDotField.textColor = NSColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1)
        let statusTextField = mkLabel("Ready", 13, .regular, NSColor(white: 1, alpha: 0.5))
        // Store references for later update
        objc_setAssociatedObject(self, &AssocKeys.statusDot,  statusDotField,  .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(self, &AssocKeys.statusText, statusTextField, .OBJC_ASSOCIATION_RETAIN)
        let statusBadge = hstack([statusDotField, statusTextField], spacing: 4)
        statusBadge.wantsLayer = true
        statusBadge.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        statusBadge.layer?.cornerRadius = 10
        statusBadge.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

        titleLeft.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(titleLeft)
        titleBar.addSubview(statusBadge)
        NSLayoutConstraint.activate([
            titleBar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            titleBar.topAnchor.constraint(equalTo: cv.topAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: 52),
            titleLeft.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 80),
            titleLeft.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            statusBadge.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -16),
            statusBadge.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
        ])

        let titleDiv = hDivider()
        titleDiv.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(titleDiv)
        NSLayoutConstraint.activate([
            titleDiv.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            titleDiv.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            titleDiv.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            titleDiv.heightAnchor.constraint(equalToConstant: 1),
        ])

        // ── Left panel (scroll) ───────────────────────────────────────
        let leftScroll = NSScrollView()
        leftScroll.drawsBackground = false
        leftScroll.hasVerticalScroller = true
        leftScroll.translatesAutoresizingMaskIntoConstraints = false

        let leftStack = NSStackView()
        leftStack.orientation = .vertical
        leftStack.spacing = 0
        leftStack.alignment = .leading
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftScroll.documentView = leftStack
        NSLayoutConstraint.activate([
            leftStack.widthAnchor.constraint(equalTo: leftScroll.contentView.widthAnchor)
        ])

        // Video
        leftStack.addArrangedSubview(sectionHeader("VIDEO", icon: "🎬"))
        [sourceField, outputField, englishField, chineseField].forEach { $0.delegate = self }
        let sourceRow = fieldRow(field: sourceField, placeholder: "/Users/…/video.mp4",
                                  buttonTitle: "Choose", action: #selector(chooseSource))
        leftStack.addArrangedSubview(padded(sourceRow))
        leftStack.addArrangedSubview(padded(fieldRow(field: outputField, placeholder: "~/Downloads",
                                                      buttonTitle: "Choose", action: #selector(chooseOutput))))

        leftStack.addArrangedSubview(spacer(8))
        leftStack.addArrangedSubview(purpleDivider())
        leftStack.addArrangedSubview(spacer(8))

        // Subtitles
        leftStack.addArrangedSubview(sectionHeader("SUBTITLES", icon: "📄"))
        leftStack.addArrangedSubview(padded(fieldRow(field: englishField, placeholder: "English .srt auto-generated after processing",
                                                      buttonTitle: "Browse", action: #selector(chooseEnglishSRT))))
        leftStack.addArrangedSubview(padded(fieldRow(field: chineseField, placeholder: "Chinese .srt, or leave empty to auto-generate",
                                                      buttonTitle: "Browse", action: #selector(chooseChineseSRT))))

        leftStack.addArrangedSubview(spacer(8))
        leftStack.addArrangedSubview(purpleDivider())
        leftStack.addArrangedSubview(spacer(8))

        // Translation
        leftStack.addArrangedSubview(sectionHeader("TRANSLATION", icon: "🌐"))
        leftStack.addArrangedSubview(padded(mkLabel("Provider", 12, .regular, NSColor(white: 1, alpha: 0.45))))
        providerPopup.removeAllItems()
        providerPopup.addItems(withTitles: ["OpenAI", "DeepSeek", "Kimi 2.5", "Google Gemini"])
        providerPopup.target = self; providerPopup.action = #selector(providerChanged)
        stylePopup(providerPopup)
        leftStack.addArrangedSubview(padded(providerPopup))

        leftStack.addArrangedSubview(padded(mkLabel("API Key", 12, .regular, NSColor(white: 1, alpha: 0.45))))
        let apiRow = NSStackView(); apiRow.orientation = .horizontal; apiRow.spacing = 6
        styleInputField(apiKeyField)
        apiKeyField.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let saveKeyBtn = accentButton("Save", action: #selector(saveAPIKey))
        apiRow.addArrangedSubview(apiKeyField); apiRow.addArrangedSubview(saveKeyBtn)
        leftStack.addArrangedSubview(padded(apiRow))

        leftStack.addArrangedSubview(padded(mkLabel("Translation Model", 12, .regular, NSColor(white: 1, alpha: 0.45))))
        let modelRow2 = NSStackView(); modelRow2.orientation = .horizontal; modelRow2.spacing = 6
        styleInputField(translateModelField)
        translateModelField.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let defaultBtn = ghostButton("Default", action: #selector(defaultTranslateModel))
        modelRow2.addArrangedSubview(translateModelField); modelRow2.addArrangedSubview(defaultBtn)
        leftStack.addArrangedSubview(padded(modelRow2))

        leftStack.addArrangedSubview(spacer(8))
        leftStack.addArrangedSubview(purpleDivider())
        leftStack.addArrangedSubview(spacer(8))

        // Output
        leftStack.addArrangedSubview(sectionHeader("OUTPUT", icon: "🔥"))
        leftStack.addArrangedSubview(padded(mkLabel("Current Step", 12, .regular, NSColor(white: 1, alpha: 0.45))))
        workflowCurrentLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        workflowCurrentLabel.textColor = .white
        workflowCurrentLabel.lineBreakMode = .byWordWrapping
        workflowCurrentLabel.maximumNumberOfLines = 0
        leftStack.addArrangedSubview(padded(workflowCurrentLabel))

        leftStack.addArrangedSubview(padded(mkLabel("Next Up", 12, .regular, NSColor(white: 1, alpha: 0.45))))
        workflowNextLabel.font = .systemFont(ofSize: 13)
        workflowNextLabel.textColor = NSColor(white: 1, alpha: 0.7)
        workflowNextLabel.lineBreakMode = .byWordWrapping
        workflowNextLabel.maximumNumberOfLines = 0
        leftStack.addArrangedSubview(padded(workflowNextLabel))
        leftStack.addArrangedSubview(spacer(8))

        let runAllBtn = NSButton(title: "", target: self, action: #selector(runAll))
        runAllBtn.isBordered = false; runAllBtn.wantsLayer = true
        runAllBtn.layer?.backgroundColor = NSColor(red: 0.48, green: 0.25, blue: 0.90, alpha: 1).cgColor
        runAllBtn.layer?.cornerRadius = 8
        runAllBtn.heightAnchor.constraint(equalToConstant: 46).isActive = true
        let runAllAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white
        ]
        runAllBtn.attributedTitle = NSAttributedString(string: "▶   Run All", attributes: runAllAttr)
        let runAllWrapper = padded(runAllBtn)
        leftStack.addArrangedSubview(runAllWrapper)

        let row1 = NSStackView(); row1.orientation = .horizontal; row1.spacing = 6
        row1.distribution = .fillEqually
        row1.addArrangedSubview(outlineButton("English SRT",     action: #selector(runEnglishSRT)))
        row1.addArrangedSubview(outlineButton("Translate EN→ZH", action: #selector(translateENToZH)))
        row1.addArrangedSubview(outlineButton("Merge ASS+Burn",  action: #selector(mergeAndBurn)))
        let stepWrapper = padded(row1)
        leftStack.addArrangedSubview(stepWrapper)
        runAllWrapper.translatesAutoresizingMaskIntoConstraints = false
        runAllWrapper.widthAnchor.constraint(equalTo: leftStack.widthAnchor).isActive = true
        runAllBtn.translatesAutoresizingMaskIntoConstraints = false
        runAllBtn.widthAnchor.constraint(equalTo: runAllWrapper.widthAnchor, constant: -32).isActive = true
        stepWrapper.translatesAutoresizingMaskIntoConstraints = false
        stepWrapper.widthAnchor.constraint(equalTo: leftStack.widthAnchor).isActive = true
        row1.translatesAutoresizingMaskIntoConstraints = false
        row1.widthAnchor.constraint(equalTo: stepWrapper.widthAnchor, constant: -32).isActive = true

        leftStack.addArrangedSubview(spacer(8))
        leftStack.addArrangedSubview(padded(mkLabel("Correction Shortcuts", 12, .regular, NSColor(white: 1, alpha: 0.45))))
        editEnglishButton.title = "Edit English SRT"
        editChineseButton.title = "Edit Chinese SRT"
        revealWorkFolderButton.title = "Reveal Work Folder"
        [editEnglishButton, editChineseButton, revealWorkFolderButton].forEach {
            $0.isBordered = false
            $0.wantsLayer = true
            $0.layer?.backgroundColor = NSColor(red: 0.18, green: 0.13, blue: 0.28, alpha: 1).cgColor
            $0.layer?.cornerRadius = 7
            $0.layer?.borderWidth = 1
            $0.layer?.borderColor = NSColor(red: 0.32, green: 0.22, blue: 0.50, alpha: 1).cgColor
            $0.contentTintColor = NSColor(white: 1, alpha: 0.8)
            $0.font = .systemFont(ofSize: 13, weight: .medium)
            $0.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        editEnglishButton.target = self; editEnglishButton.action = #selector(openEnglishSRT)
        editChineseButton.target = self; editChineseButton.action = #selector(openChineseSRT)
        revealWorkFolderButton.target = self; revealWorkFolderButton.action = #selector(revealWorkFolder)
        let correctionRow = NSStackView()
        correctionRow.orientation = .horizontal
        correctionRow.spacing = 6
        correctionRow.distribution = .fillEqually
        correctionRow.addArrangedSubview(editEnglishButton)
        correctionRow.addArrangedSubview(editChineseButton)
        correctionRow.addArrangedSubview(revealWorkFolderButton)
        leftStack.addArrangedSubview(padded(correctionRow))

        leftStack.addArrangedSubview(spacer(8))
        leftStack.addArrangedSubview(padded(mkLabel("Latest Output", 12, .regular, NSColor(white: 1, alpha: 0.45))))
        latestOutputTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        latestOutputTitleLabel.textColor = .white
        latestOutputPathLabel.font = .systemFont(ofSize: 12)
        latestOutputPathLabel.textColor = NSColor(white: 1, alpha: 0.6)
        latestOutputPathLabel.lineBreakMode = .byWordWrapping
        latestOutputPathLabel.maximumNumberOfLines = 0
        leftStack.addArrangedSubview(padded(latestOutputTitleLabel))
        leftStack.addArrangedSubview(padded(latestOutputPathLabel))
        openLatestOutputButton.title = "Open Latest Output"
        revealLatestOutputButton.title = "Reveal in Finder"
        previewSubtitlesButton.title = "Preview Subtitles"
        [openLatestOutputButton, revealLatestOutputButton, previewSubtitlesButton].forEach {
            $0.isBordered = false
            $0.wantsLayer = true
            $0.layer?.backgroundColor = NSColor(red: 0.18, green: 0.13, blue: 0.28, alpha: 1).cgColor
            $0.layer?.cornerRadius = 7
            $0.layer?.borderWidth = 1
            $0.layer?.borderColor = NSColor(red: 0.32, green: 0.22, blue: 0.50, alpha: 1).cgColor
            $0.contentTintColor = NSColor(white: 1, alpha: 0.8)
            $0.font = .systemFont(ofSize: 13, weight: .medium)
            $0.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        openLatestOutputButton.target = self; openLatestOutputButton.action = #selector(openLatestOutput)
        revealLatestOutputButton.target = self; revealLatestOutputButton.action = #selector(revealLatestOutput)
        previewSubtitlesButton.target = self; previewSubtitlesButton.action = #selector(previewSubtitles)
        let latestOutputRow = NSStackView()
        latestOutputRow.orientation = .horizontal
        latestOutputRow.spacing = 6
        latestOutputRow.distribution = .fillEqually
        latestOutputRow.addArrangedSubview(openLatestOutputButton)
        latestOutputRow.addArrangedSubview(revealLatestOutputButton)
        latestOutputRow.addArrangedSubview(previewSubtitlesButton)
        leftStack.addArrangedSubview(padded(latestOutputRow))

        leftStack.addArrangedSubview(spacer(8))
        leftStack.addArrangedSubview(purpleDivider())
        leftStack.addArrangedSubview(spacer(8))

        // Advanced (collapsible)
        let advancedToggle = NSButton(title: "", target: self, action: #selector(toggleAdvanced))
        advancedToggle.isBordered = false
        let advancedHeader = NSStackView(); advancedHeader.orientation = .horizontal; advancedHeader.spacing = 6
        advancedChevron.font = .systemFont(ofSize: 15); advancedChevron.textColor = NSColor(white: 1, alpha: 0.45)
        advancedHeader.addArrangedSubview(advancedChevron)
        advancedHeader.addArrangedSubview(mkLabel("ADVANCED", 11, .bold, NSColor(white: 1, alpha: 0.4)))
        advancedHeader.addArrangedSubview(NSView())
        let advancedClickRow = NSView()
        advancedClickRow.translatesAutoresizingMaskIntoConstraints = false
        advancedHeader.translatesAutoresizingMaskIntoConstraints = false
        advancedClickRow.addSubview(advancedHeader)
        pin(advancedHeader, to: advancedClickRow)
        advancedToggle.translatesAutoresizingMaskIntoConstraints = false
        advancedClickRow.addSubview(advancedToggle)
        pin(advancedToggle, to: advancedClickRow)
        leftStack.addArrangedSubview(padded(advancedClickRow))

        advancedStack.orientation = .vertical
        advancedStack.spacing = 8
        advancedStack.alignment = .leading
        advancedStack.isHidden = true

        advancedStack.addArrangedSubview(padded(mkLabel("Whisper Model", 12, .regular, NSColor(white: 1, alpha: 0.45))))
        modelPopup.removeAllItems()
        modelPopup.addItems(withTitles: ["turbo", "small", "medium", "large-v3"])
        stylePopup(modelPopup)
        advancedStack.addArrangedSubview(padded(modelPopup))

        advancedStack.addArrangedSubview(padded(mkLabel("Sync Offset (seconds)", 12, .regular, NSColor(white: 1, alpha: 0.45))))
        syncOffsetField.placeholderString = "0.0  (e.g. -0.5 to shift earlier)"
        syncOffsetField.stringValue = "0.0"
        styleInputField(syncOffsetField)
        syncOffsetField.heightAnchor.constraint(equalToConstant: 36).isActive = true
        advancedStack.addArrangedSubview(padded(syncOffsetField))

        advancedStack.addArrangedSubview(padded(mkLabel("Tools", 12, .regular, NSColor(white: 1, alpha: 0.45))))
        for (lbl, field, sel) in [
            ("ffmpeg",   ffmpegField,  #selector(chooseFFmpeg)),
            ("ffprobe",  ffprobeField, #selector(chooseFFprobe)),
            ("whisper",  whisperField, #selector(chooseWhisper)),
            ("CJK Font", fontField,    #selector(chooseFont)),
        ] as [(String, NSTextField, Selector)] {
            styleInputField(field)
            field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            field.heightAnchor.constraint(equalToConstant: 36).isActive = true
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let findBtn = ghostButton("Find", action: sel)
            findBtn.setContentHuggingPriority(.required, for: .horizontal)
            let toolRow = NSStackView(); toolRow.orientation = .horizontal; toolRow.spacing = 6
            toolRow.addArrangedSubview(field); toolRow.addArrangedSubview(findBtn)
            let lbl2 = mkLabel(lbl, 12, .regular, NSColor(white: 1, alpha: 0.4))
            let col = NSStackView(); col.orientation = .vertical; col.spacing = 3; col.alignment = .leading
            col.addArrangedSubview(lbl2); col.addArrangedSubview(toolRow)
            col.translatesAutoresizingMaskIntoConstraints = false
            toolRow.translatesAutoresizingMaskIntoConstraints = false
            advancedStack.addArrangedSubview(padded(col))
        }
        let advancedWrapper = padded(advancedStack)
        leftStack.addArrangedSubview(advancedWrapper)
        advancedWrapper.translatesAutoresizingMaskIntoConstraints = false
        advancedWrapper.widthAnchor.constraint(equalTo: leftStack.widthAnchor).isActive = true
        advancedStack.translatesAutoresizingMaskIntoConstraints = false
        advancedStack.widthAnchor.constraint(equalTo: advancedWrapper.widthAnchor, constant: -32).isActive = true
        for sub in advancedStack.arrangedSubviews {
            sub.translatesAutoresizingMaskIntoConstraints = false
            sub.widthAnchor.constraint(equalTo: advancedStack.widthAnchor).isActive = true
            if let wrapper = sub as? NSStackView,
               let content = wrapper.arrangedSubviews.first {
                content.translatesAutoresizingMaskIntoConstraints = false
                content.widthAnchor.constraint(equalTo: wrapper.widthAnchor, constant: -32).isActive = true
                if let col = content as? NSStackView,
                   let toolRow = col.arrangedSubviews.last as? NSStackView {
                    toolRow.translatesAutoresizingMaskIntoConstraints = false
                    toolRow.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
                }
            }
        }

        leftStack.addArrangedSubview(spacer(8))

        // Status bar
        let statusBar = NSStackView(); statusBar.orientation = .horizontal; statusBar.spacing = 8
        statusBar.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = NSColor(red: 0.10, green: 0.08, blue: 0.16, alpha: 1).cgColor
        let statusIndicator = NSTextField(labelWithString: "● Ready")
        statusIndicator.font = .systemFont(ofSize: 13)
        statusIndicator.textColor = NSColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1)
        objc_setAssociatedObject(self, &AssocKeys.statusBar, statusIndicator, .OBJC_ASSOCIATION_RETAIN)
        cancelButton.title = "Cancel"
        cancelButton.isBordered = false; cancelButton.wantsLayer = true
        cancelButton.layer?.backgroundColor = NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.2).cgColor
        cancelButton.layer?.cornerRadius = 6
        cancelButton.contentTintColor = NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
        cancelButton.font = .systemFont(ofSize: 13)
        cancelButton.target = self; cancelButton.action = #selector(cancelJob)
        cancelButton.isEnabled = false
        cancelButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        progressBar.style = .bar; progressBar.isIndeterminate = false
        progressBar.minValue = 0; progressBar.maxValue = 1
        progressBar.isHidden = true
        statusBar.addArrangedSubview(statusIndicator)
        statusBar.addArrangedSubview(NSView())
        statusBar.addArrangedSubview(cancelButton)
        leftStack.addArrangedSubview(statusBar)
        leftStack.addArrangedSubview(spacer(8))

        // ── Right panel ───────────────────────────────────────────────
        let rightPanel = NSView()
        rightPanel.wantsLayer = true
        rightPanel.layer?.backgroundColor = NSColor(red: 0.06, green: 0.05, blue: 0.10, alpha: 1).cgColor
        rightPanel.translatesAutoresizingMaskIntoConstraints = false

        // Top info bar (file + status)
        let infoBar = NSView()
        infoBar.wantsLayer = true
        infoBar.layer?.backgroundColor = NSColor(red: 0.10, green: 0.08, blue: 0.18, alpha: 1).cgColor
        infoBar.translatesAutoresizingMaskIntoConstraints = false

        let thumbView = NSView()
        thumbView.wantsLayer = true
        thumbView.layer?.backgroundColor = NSColor(red: 0.15, green: 0.12, blue: 0.22, alpha: 1).cgColor
        thumbView.layer?.cornerRadius = 6
        thumbView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        thumbView.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let thumbIcon = mkLabel("🎬", 20, .regular, NSColor(white: 1, alpha: 0.4))
        thumbIcon.translatesAutoresizingMaskIntoConstraints = false
        thumbView.addSubview(thumbIcon)
        NSLayoutConstraint.activate([
            thumbIcon.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor),
            thumbIcon.centerYAnchor.constraint(equalTo: thumbView.centerYAnchor),
        ])

        let fileNameLabel = mkLabel("No file selected", 15, .semibold, .white)
        let filePathLabel = mkLabel("Drag a video file or use Add Files", 12, .regular, NSColor(white: 1, alpha: 0.4))
        objc_setAssociatedObject(self, &AssocKeys.fileNameLabel, fileNameLabel, .OBJC_ASSOCIATION_RETAIN)
        let fileInfo = vstack([filePathLabel, fileNameLabel], spacing: 3)

        let pendingBadge = NSView()
        pendingBadge.wantsLayer = true
        pendingBadge.layer?.backgroundColor = NSColor(red: 0.48, green: 0.25, blue: 0.90, alpha: 0.3).cgColor
        pendingBadge.layer?.cornerRadius = 8
        pendingBadge.layer?.borderWidth = 1
        pendingBadge.layer?.borderColor = NSColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 0.6).cgColor
        let pendingLabel = mkLabel("PENDING", 11, .bold, NSColor(red: 0.7, green: 0.55, blue: 1.0, alpha: 1))
        pendingLabel.translatesAutoresizingMaskIntoConstraints = false
        pendingBadge.addSubview(pendingLabel)
        NSLayoutConstraint.activate([
            pendingLabel.leadingAnchor.constraint(equalTo: pendingBadge.leadingAnchor, constant: 8),
            pendingLabel.trailingAnchor.constraint(equalTo: pendingBadge.trailingAnchor, constant: -8),
            pendingLabel.centerYAnchor.constraint(equalTo: pendingBadge.centerYAnchor),
            pendingBadge.heightAnchor.constraint(equalToConstant: 22),
        ])
        objc_setAssociatedObject(self, &AssocKeys.pendingBadge, pendingLabel, .OBJC_ASSOCIATION_RETAIN)

        let infoContent = hstack([thumbView, fileInfo, NSView(), pendingBadge], spacing: 12)
        infoContent.translatesAutoresizingMaskIntoConstraints = false
        infoBar.addSubview(infoContent)
        NSLayoutConstraint.activate([
            infoBar.heightAnchor.constraint(equalToConstant: 68),
            infoContent.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor, constant: 16),
            infoContent.trailingAnchor.constraint(equalTo: infoBar.trailingAnchor, constant: -16),
            infoContent.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
        ])

        // Log header
        let logHeader = NSView()
        logHeader.wantsLayer = true
        logHeader.layer?.backgroundColor = NSColor(red: 0.09, green: 0.07, blue: 0.15, alpha: 1).cgColor
        logHeader.translatesAutoresizingMaskIntoConstraints = false
        let logIcon = mkLabel("⬛", 13, .regular, NSColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 1))
        let logTitle = mkLabel("PROCESS LOG", 12, .bold, NSColor(white: 1, alpha: 0.5))
        let clearLogBtn = ghostButton("Clear", action: #selector(clearLog))
        let logHead = hstack([logIcon, logTitle, NSView(), clearLogBtn], spacing: 8)
        logHead.translatesAutoresizingMaskIntoConstraints = false
        logHeader.addSubview(logHead)
        NSLayoutConstraint.activate([
            logHeader.heightAnchor.constraint(equalToConstant: 36),
            logHead.leadingAnchor.constraint(equalTo: logHeader.leadingAnchor, constant: 12),
            logHead.trailingAnchor.constraint(equalTo: logHeader.trailingAnchor, constant: -12),
            logHead.centerYAnchor.constraint(equalTo: logHeader.centerYAnchor),
        ])

        // Log view
        logView.isEditable = false
        logView.drawsBackground = false
        logView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        logView.textColor = NSColor(red: 0.2, green: 0.9, blue: 0.5, alpha: 1)
        logView.textContainerInset = NSSize(width: 12, height: 12)
        let logScroll = NSScrollView()
        logScroll.drawsBackground = false
        logScroll.hasVerticalScroller = true
        logScroll.documentView = logView
        logScroll.contentView.backgroundColor = NSColor(red: 0.06, green: 0.04, blue: 0.10, alpha: 1)
        logScroll.translatesAutoresizingMaskIntoConstraints = false

        // Vertical divider between panels
        let vDiv = NSView()
        vDiv.wantsLayer = true
        vDiv.layer?.backgroundColor = NSColor(red: 0.25, green: 0.18, blue: 0.38, alpha: 1).cgColor
        vDiv.translatesAutoresizingMaskIntoConstraints = false

        rightPanel.addSubview(infoBar)
        rightPanel.addSubview(logHeader)
        rightPanel.addSubview(logScroll)
        NSLayoutConstraint.activate([
            infoBar.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            infoBar.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
            infoBar.topAnchor.constraint(equalTo: rightPanel.topAnchor),
            logHeader.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            logHeader.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
            logHeader.topAnchor.constraint(equalTo: infoBar.bottomAnchor),
            logScroll.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            logScroll.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
            logScroll.topAnchor.constraint(equalTo: logHeader.bottomAnchor),
            logScroll.bottomAnchor.constraint(equalTo: rightPanel.bottomAnchor),
        ])

        // Batch queue (bottom of left panel)
        leftStack.addArrangedSubview(purpleDivider())
        leftStack.addArrangedSubview(spacer(4))
        let batchTitle = mkLabel("BATCH QUEUE", 11, .bold, NSColor(white: 1, alpha: 0.4))
        leftStack.addArrangedSubview(padded(batchTitle))

        let col1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        col1.title = "File"; col1.width = 220
        let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        col2.title = "Status"; col2.width = 120
        batchTableView.addTableColumn(col1)
        batchTableView.addTableColumn(col2)
        batchTableView.dataSource = self; batchTableView.delegate = self
        batchTableView.backgroundColor = NSColor(red: 0.08, green: 0.06, blue: 0.13, alpha: 1)
        batchTableView.allowsMultipleSelection = true
        let batchScroll2 = NSScrollView()
        batchScroll2.drawsBackground = false
        batchScroll2.hasVerticalScroller = true
        batchScroll2.documentView = batchTableView
        batchScroll2.heightAnchor.constraint(equalToConstant: 90).isActive = true
        leftStack.addArrangedSubview(padded(batchScroll2))

        let batchBtns = NSStackView(); batchBtns.orientation = .horizontal; batchBtns.spacing = 6
        batchBtns.addArrangedSubview(ghostButton("Add Files…", action: #selector(addBatchFiles)))
        batchBtns.addArrangedSubview(ghostButton("Remove", action: #selector(removeBatchFiles)))
        batchBtns.addArrangedSubview(ghostButton("Run Batch", action: #selector(runBatch)))
        batchBtns.addArrangedSubview(NSView())
        leftStack.addArrangedSubview(padded(batchBtns))
        leftStack.addArrangedSubview(spacer(8))

        // ── Layout: left | divider | right ───────────────────────────
        cv.addSubview(leftScroll)
        cv.addSubview(vDiv)
        cv.addSubview(rightPanel)
        NSLayoutConstraint.activate([
            leftScroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            leftScroll.topAnchor.constraint(equalTo: titleDiv.bottomAnchor),
            leftScroll.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            leftScroll.widthAnchor.constraint(equalTo: cv.widthAnchor, multiplier: 0.40),
            vDiv.leadingAnchor.constraint(equalTo: leftScroll.trailingAnchor),
            vDiv.topAnchor.constraint(equalTo: titleDiv.bottomAnchor),
            vDiv.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            vDiv.widthAnchor.constraint(equalToConstant: 1),
            rightPanel.leadingAnchor.constraint(equalTo: vDiv.trailingAnchor),
            rightPanel.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            rightPanel.topAnchor.constraint(equalTo: titleDiv.bottomAnchor),
            rightPanel.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        // Wire up the runner
        runner.onLog = { [weak self] msg in DispatchQueue.main.async { self?.log(msg) } }
        runner.onProgress = { [weak self] p in DispatchQueue.main.async { self?.updateProgress(p) } }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI helpers

    private func mkLabel(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.textColor = color; return f
    }

    private func hstack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = .horizontal; s.spacing = spacing; return s
    }

    private func vstack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = .vertical; s.spacing = spacing
        s.alignment = .leading; return s
    }

    private func pin(_ child: NSView, to parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    private func sectionHeader(_ title: String, icon: String) -> NSView {
        let s = NSStackView()
        s.orientation = .horizontal; s.spacing = 6
        s.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 4, right: 16)
        let iconL = mkLabel(icon, 14, .regular, NSColor(white: 1, alpha: 0.5))
        let titleL = mkLabel(title, 11, .bold, NSColor(white: 1, alpha: 0.4))
        s.addArrangedSubview(iconL); s.addArrangedSubview(titleL)
        return s
    }

    private func fieldRow(field: NSTextField, placeholder: String, buttonTitle: String, action: Selector) -> NSStackView {
        field.placeholderString = placeholder
        styleInputField(field)
        field.heightAnchor.constraint(equalToConstant: 40).isActive = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let btn = ghostButton(buttonTitle, action: action)
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 6
        row.addArrangedSubview(field); row.addArrangedSubview(btn)
        return row
    }

    private func padded(_ view: NSView) -> NSView {
        let wrapper = NSStackView()
        wrapper.orientation = .vertical
        wrapper.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 6, right: 16)
        wrapper.addArrangedSubview(view)
        return wrapper
    }

    private func spacer(_ h: CGFloat) -> NSView {
        let v = NSView(); v.heightAnchor.constraint(equalToConstant: h).isActive = true; return v
    }

    private func purpleDivider() -> NSView {
        let v = NSView(); v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(red: 0.28, green: 0.18, blue: 0.45, alpha: 1).cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func hDivider() -> NSView {
        let v = NSView(); v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(red: 0.20, green: 0.15, blue: 0.30, alpha: 1).cgColor
        return v
    }

    private func styleInputField(_ f: NSTextField) {
        f.wantsLayer = true
        f.layer?.backgroundColor = NSColor(red: 0.13, green: 0.10, blue: 0.20, alpha: 1).cgColor
        f.layer?.cornerRadius = 7
        f.layer?.borderWidth = 1
        f.layer?.borderColor = NSColor(red: 0.32, green: 0.22, blue: 0.50, alpha: 1).cgColor
        f.textColor = .white; f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none
        f.font = .systemFont(ofSize: 13)
        if let cell = f.cell as? NSTextFieldCell {
            cell.placeholderAttributedString = NSAttributedString(
                string: f.placeholderString ?? "",
                attributes: [.foregroundColor: NSColor(white: 1, alpha: 0.25),
                             .font: NSFont.systemFont(ofSize: 13)])
        }
    }

    private func stylePopup(_ p: NSPopUpButton) {
        p.wantsLayer = true
        p.layer?.backgroundColor = NSColor(red: 0.13, green: 0.10, blue: 0.20, alpha: 1).cgColor
        p.layer?.cornerRadius = 7
        p.layer?.borderWidth = 1
        p.layer?.borderColor = NSColor(red: 0.32, green: 0.22, blue: 0.50, alpha: 1).cgColor
        p.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    private func ghostButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false; b.wantsLayer = true
        b.layer?.backgroundColor = NSColor(red: 0.18, green: 0.13, blue: 0.28, alpha: 1).cgColor
        b.layer?.cornerRadius = 7
        b.layer?.borderWidth = 1
        b.layer?.borderColor = NSColor(red: 0.32, green: 0.22, blue: 0.50, alpha: 1).cgColor
        b.contentTintColor = NSColor(white: 1, alpha: 0.75)
        b.font = .systemFont(ofSize: 13, weight: .medium)
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let w = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: w + 20).isActive = true
        return b
    }

    private func accentButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false; b.wantsLayer = true
        b.layer?.backgroundColor = NSColor(red: 0.48, green: 0.25, blue: 0.90, alpha: 1).cgColor
        b.layer?.cornerRadius = 7
        b.contentTintColor = .white
        b.font = .systemFont(ofSize: 13, weight: .semibold)
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let w = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: w + 20).isActive = true
        return b
    }

    private func outlineButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false; b.wantsLayer = true
        b.layer?.backgroundColor = NSColor(red: 0.15, green: 0.11, blue: 0.23, alpha: 1).cgColor
        b.layer?.cornerRadius = 7
        b.layer?.borderWidth = 1
        b.layer?.borderColor = NSColor(red: 0.40, green: 0.28, blue: 0.62, alpha: 1).cgColor
        b.contentTintColor = .white
        b.font = .systemFont(ofSize: 14, weight: .medium)
        b.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return b
    }

    @objc func clearLog() {
        logView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

        // MARK: - Progress

    func updateProgress(_ p: PipelineProgress) {
        if p.fraction >= 0 {
            progressBar.doubleValue = p.fraction
        }
        var label = p.step
        if let t = p.ffmpegTime { label += "  \(t)" }
        if let sb = objc_getAssociatedObject(self, &AssocKeys.statusBar) as? NSTextField {
            sb.stringValue = "● " + label
            sb.textColor = NSColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1)
        }
        updateWorkflowUI(progressStep: p.step)
    }

    // MARK: - Job management

    func startJob(_ work: @escaping () async throws -> Void) {
        guard currentTask == nil else {
            alert("A job is already running.")
            return
        }
        saveSettings()
        cancelButton.isEnabled = true
        progressBar.doubleValue = 0
        if let sb = objc_getAssociatedObject(self, &AssocKeys.statusBar) as? NSTextField {
            sb.stringValue = "● Running…"
            sb.textColor = NSColor(red: 0.95, green: 0.75, blue: 0.2, alpha: 1)
        }
        currentTask = Task {
            do {
                try await work()
                await MainActor.run { self.log("✅ Done.") }
            } catch SubtitleError.cancelled {
                await MainActor.run { self.log("⚠️ Cancelled.") }
            } catch {
                await MainActor.run {
                    self.log("❌ \(error.localizedDescription)")
                    self.alert(error.localizedDescription)
                }
            }
            await MainActor.run {
                self.currentTask = nil
                self.cancelButton.isEnabled = false
                self.progressBar.doubleValue = 0
                if let sb = objc_getAssociatedObject(self, &AssocKeys.statusBar) as? NSTextField {
                    sb.stringValue = "● Ready"
                    sb.textColor = NSColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1)
                }
                self.updateWorkflowUI()
            }
        }
    }

    @objc func cancelJob() {
        runner.cancel()
        currentTask?.cancel()
    }

    // MARK: - Actions

    @objc func checkDependencies() {
        startJob {
            self.log("Checking dependencies…")
            let paths = await MainActor.run { [
                ("ffmpeg",  self.ffmpegField.stringValue),
                ("ffprobe", self.ffprobeField.stringValue),
                ("whisper", self.whisperField.stringValue),
                ("Font",    self.fontField.stringValue)
            ] }
            for (name, path) in paths {
                let ok = FileManager.default.fileExists(atPath: path)
                self.log("\(name): \(ok ? "✅" : "❌ Missing")  \(path)")
            }
        }
    }

    @objc func runEnglishSRT() {
        startJob {
            self.syncRunnerPaths()
            let source = try self.requireSource()
            let out    = try self.requireOutputFolder()
            let srtURL = try await self.runner.runEnglishSRT(
                source: source,
                outputFolder: out,
                whisperModel: self.selectedModel()
            )
            await MainActor.run {
                self.englishField.stringValue = srtURL.path
                self.rememberOutput(srtURL, summary: "English SRT ready for review and cleanup.")
            }
        }
    }

    @objc func translateENToZH() {
        startJob {
            self.syncRunnerPaths()
            let source = try self.requireSource()
            let paths  = Paths(source: source, outputRoot: try self.requireOutputFolder())
            let enPath = self.englishField.stringValue.isEmpty ? paths.enSRT.path : self.englishField.stringValue
            let apiKey = self.apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let provider = self.selectedProvider()
            guard FileManager.default.fileExists(atPath: enPath) else {
                throw SubtitleError.missingFile(enPath)
            }
            guard !apiKey.isEmpty else { throw SubtitleError.missingAPIKey(provider) }

            let zhURL = try await self.runner.translateSRT(
                enSRT: URL(fileURLWithPath: enPath),
                zhSRT: paths.zhSRT,
                provider: self.selectedProvider(),
                model: self.translateModel(),
                apiKey: apiKey
            )
            await MainActor.run {
                self.chineseField.stringValue = zhURL.path
                self.rememberOutput(zhURL, summary: "Chinese SRT ready. Open it if you want to refine the translation.")
            }
        }
    }

    @objc func mergeAndBurn() {
        startJob {
            self.syncRunnerPaths()
            let source = try self.requireSource()
            let out    = try self.requireOutputFolder()
            let enOverride = self.englishField.stringValue
            let zhOverride = self.chineseField.stringValue
            let burned = try await self.runner.mergeAndBurn(
                source: source,
                outputFolder: out,
                enSRTOverride: enOverride,
                zhSRTOverride: zhOverride
            )
            await MainActor.run {
                self.rememberOutput(burned, summary: "Burned video ready. Open it to spot-check subtitle placement.")
            }
        }
    }

    @objc func runAll() {
        startJob {
            self.syncRunnerPaths()
            let source = try self.requireSource()
            let out    = try self.requireOutputFolder()
            let apiKey = self.apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let provider = self.selectedProvider()
            let enOverride = self.englishField.stringValue
            let zhOverride = self.chineseField.stringValue
            let wModel = self.selectedModel()
            guard !apiKey.isEmpty else { throw SubtitleError.missingAPIKey(provider) }
            let burned = try await self.runner.runAll(
                source: source,
                outputFolder: out,
                whisperModel: wModel,
                provider: self.selectedProvider(),
                translateModel: self.translateModel(),
                apiKey: apiKey,
                enSRTOverride: enOverride,
                zhSRTOverride: zhOverride
            )
            let paths = Paths(source: source, outputRoot: out)
            await MainActor.run {
                self.englishField.stringValue = paths.enSRT.path
                self.chineseField.stringValue = paths.zhSRT.path
                self.rememberOutput(burned, summary: "Full pipeline complete. Review the burned video or reopen the SRT files for tweaks.")
            }
        }
    }

    // MARK: - Batch

    @objc func addBatchFiles() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) { panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie] } else { panel.allowedFileTypes = ["mov", "mp4", "m4v"] }
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            addToBatch(urls: panel.urls)
        }
    }

    @objc func removeBatchFiles() {
        let selected = batchTableView.selectedRowIndexes.sorted().reversed()
        for idx in selected { batchJobs.remove(at: idx) }
        batchTableView.reloadData()
    }

    @objc func runBatch() {
        guard !batchJobs.isEmpty else { alert("Add files to the batch queue first."); return }
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { alert("Enter an API key to run batch translation."); return }

        startJob {
            self.syncRunnerPaths()
            let out = try self.requireOutputFolder()
            for (i, _) in self.batchJobs.enumerated() {
                let job = self.batchJobs[i]
                self.batchJobs[i].status = .running(step: "Starting…")
                self.batchTableView.reloadData()
                do {
                    _ = try await self.runner.runAll(
                        source: job.sourceURL,
                        outputFolder: out,
                        whisperModel: self.selectedModel(),
                        provider: self.selectedProvider(),
                        translateModel: self.translateModel(),
                        apiKey: apiKey,
                        enSRTOverride: "",
                        zhSRTOverride: ""
                    )
                    self.batchJobs[i].status = .done
                    self.batchTableView.reloadData()
                    let paths = Paths(source: job.sourceURL, outputRoot: out)
                    await MainActor.run {
                        self.rememberOutput(paths.burned, summary: "Latest batch item finished. Open it or reveal the work folder.")
                    }
                } catch SubtitleError.cancelled {
                    self.batchJobs[i].status = .cancelled
                    self.batchTableView.reloadData()
                    return  // stop batch on cancel
                } catch {
                    self.batchJobs[i].status = .failed(error.localizedDescription)
                    self.batchTableView.reloadData()
                }
            }
        }
    }

    func addToBatch(urls: [URL]) {
        let videoExtensions = ["mov", "mp4", "m4v"]
        let newJobs = urls
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .filter { url in !batchJobs.contains(where: { $0.sourceURL == url }) }
            .map { BatchJob(sourceURL: $0) }
        batchJobs.append(contentsOf: newJobs)
        batchTableView.reloadData()
        log("Added \(newJobs.count) file(s) to batch queue.")
        if let first = newJobs.first {
            if sourceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sourceField.stringValue = first.sourceURL.path
            }
            updateSelectedSourceUI(first.sourceURL)
        }
        if let badge = objc_getAssociatedObject(self, &AssocKeys.pendingBadge) as? NSTextField {
            badge.stringValue = batchJobs.isEmpty ? "" : "PENDING"
        }
    }

    // MARK: - File choosers

    @objc func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            outputField.stringValue = url.path
            Settings.outputFolder = url.path
            updateWorkflowUI()
        }
    }

    @objc func chooseSource() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        } else {
            panel.allowedFileTypes = ["mov", "mp4", "m4v"]
        }
        if panel.runModal() == .OK, let url = panel.url {
            sourceField.stringValue = url.path
            updateSelectedSourceUI(url)
            updateWorkflowUI()
        }
    }

    @objc func chooseEnglishSRT() { chooseFile(into: englishField, types: ["srt"]) }
    @objc func chooseChineseSRT() { chooseFile(into: chineseField, types: ["srt"]) }
    @objc func chooseFFmpeg()     { chooseFile(into: ffmpegField,  types: nil) }
    @objc func chooseFFprobe()    { chooseFile(into: ffprobeField, types: nil) }
    @objc func chooseWhisper()    { chooseFile(into: whisperField, types: nil) }
    @objc func chooseFont() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) { panel.allowedContentTypes = [.font] } else { panel.allowedFileTypes = ["ttf", "otf", "ttc"] }
        panel.directoryURL = URL(fileURLWithPath: "/System/Library/Fonts")
        if panel.runModal() == .OK, let url = panel.url {
            fontField.stringValue = url.path
            Settings.fontPath = url.path
        }
    }

    @objc func saveAPIKey() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            KeychainStore.delete(for: selectedProvider())
            log("API key cleared from Keychain.")
        } else {
            KeychainStore.save(key: key, for: selectedProvider())
            log("API key saved to Keychain for \(selectedProvider()).")
        }
    }

    @objc func defaultTranslateModel() {
        translateModelField.stringValue = Settings.defaultModel(for: selectedProvider())
    }

    @objc func providerChanged() {
        translateModelField.stringValue = Settings.defaultModel(for: selectedProvider())
        // Load saved key for this provider from Keychain
        apiKeyField.stringValue = KeychainStore.load(for: selectedProvider()) ?? ""
        Settings.translateProvider = selectedProvider()
        updateWorkflowUI()
    }

    @objc func toggleAdvanced() {
        advancedExpanded.toggle()
        advancedChevron.stringValue = advancedExpanded ? "▾" : "›"
        advancedStack.isHidden = !advancedExpanded
    }

    @objc func settingChanged() { saveSettings() }

    @objc func openEnglishSRT() { openEditableFile(bestEnglishSRTURL()) }
    @objc func openChineseSRT() { openEditableFile(bestChineseSRTURL()) }
    @objc func revealWorkFolder() {
        guard let url = workFolderURL(), FileManager.default.fileExists(atPath: url.path) else {
            alert("Run at least one step first so the subtitle work folder exists.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    @objc func openLatestOutput() {
        guard let url = lastOutputURL, FileManager.default.fileExists(atPath: url.path) else {
            alert("No recent output is ready yet.")
            return
        }
        NSWorkspace.shared.open(url)
    }
    @objc func revealLatestOutput() {
        guard let url = lastOutputURL, FileManager.default.fileExists(atPath: url.path) else {
            alert("No recent output is ready yet.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    @objc func previewSubtitles() {
        guard let assets = previewLaunchAssets() else {
            return
        }

        do {
            let cues = try previewCues(from: assets.cueSourceURL, label: assets.cueSourceLabel)
            showPreviewWindow(cues: cues, assets: assets)
        } catch {
            alert(error.localizedDescription)
        }
    }

    func chooseFile(into field: NSTextField, types: [String]?) {
        let panel = NSOpenPanel()
        if let types {
            panel.allowedFileTypes = types
        }
        if panel.runModal() == .OK, let url = panel.url {
            field.stringValue = url.path
            updateWorkflowUI()
        }
    }

    // MARK: - Helpers

    func syncRunnerPaths() {
        runner.ffmpegPath  = ffmpegField.stringValue
        runner.ffprobePath = ffprobeField.stringValue
        runner.whisperPath = whisperField.stringValue
        runner.fontPath    = fontField.stringValue.isEmpty ? Settings.preferredSystemFont() : fontField.stringValue
        runner.syncOffsetSeconds = Double(syncOffsetField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0.0
    }

    func requireSource() throws -> URL {
        let typedPath = sourceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedPath.isEmpty {
            guard FileManager.default.fileExists(atPath: typedPath) else { throw SubtitleError.missingFile(typedPath) }
            return URL(fileURLWithPath: typedPath)
        }
        // Use first queued job if batch is populated and none manually set
        if let first = batchJobs.first(where: { $0.status == .queued }) {
            return first.sourceURL
        }
        // Fallback: check if there's only one job in queue
        if let first = batchJobs.first {
            return first.sourceURL
        }
        throw SubtitleError.missingSource
    }

    func requireOutputFolder() throws -> URL {
        let path = outputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw SubtitleError.missingFile("Output folder not set.") }
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return URL(fileURLWithPath: path)
    }

    func selectedModel() -> String {
        modelPopup.titleOfSelectedItem ?? "turbo"
    }

    func selectedProvider() -> String {
        providerPopup.titleOfSelectedItem ?? "OpenAI"
    }

    func updateSelectedSourceUI(_ url: URL) {
        if let lbl = objc_getAssociatedObject(self, &AssocKeys.fileNameLabel) as? NSTextField {
            lbl.stringValue = url.lastPathComponent
        }
        updateWorkflowUI()
    }

    func translateModel() -> String {
        let v = translateModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? Settings.defaultModel(for: selectedProvider()) : v
    }

    func rememberOutput(_ url: URL, summary: String) {
        lastOutputURL = url
        latestOutputTitleLabel.stringValue = url.lastPathComponent
        latestOutputPathLabel.stringValue = summary + "\n" + url.path
        updateOutputButtons()
        updateWorkflowUI()
    }

    func updateOutputButtons() {
        let hasLatest = lastOutputURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        openLatestOutputButton.isEnabled = hasLatest
        revealLatestOutputButton.isEnabled = hasLatest
        previewSubtitlesButton.isEnabled = derivedPaths() != nil
        editEnglishButton.isEnabled = bestEnglishSRTURL() != nil
        editChineseButton.isEnabled = bestChineseSRTURL() != nil
        revealWorkFolderButton.isEnabled = workFolderURL().map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func bestEnglishSRTURL() -> URL? {
        let typed = englishField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, FileManager.default.fileExists(atPath: typed) {
            return URL(fileURLWithPath: typed)
        }
        if let paths = derivedPaths(), FileManager.default.fileExists(atPath: paths.enSRT.path) {
            return paths.enSRT
        }
        return nil
    }

    func bestChineseSRTURL() -> URL? {
        let typed = chineseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, FileManager.default.fileExists(atPath: typed) {
            return URL(fileURLWithPath: typed)
        }
        if let paths = derivedPaths(), FileManager.default.fileExists(atPath: paths.zhSRT.path) {
            return paths.zhSRT
        }
        return nil
    }

    func openEditableFile(_ url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            alert("That subtitle file is not ready yet.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func currentSourceVideoURL() -> URL? {
        let sourcePath = sourceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourcePath.isEmpty, FileManager.default.fileExists(atPath: sourcePath) else {
            return nil
        }
        return URL(fileURLWithPath: sourcePath)
    }

    func derivedPaths() -> Paths? {
        let sourcePath = sourceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputPath = outputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourcePath.isEmpty, !outputPath.isEmpty else { return nil }
        return Paths(source: URL(fileURLWithPath: sourcePath), outputRoot: URL(fileURLWithPath: outputPath))
    }

    func workFolderURL() -> URL? {
        derivedPaths()?.root
    }

    func syncLatestPreviewAssets() {
        latestSourceVideoURL = currentSourceVideoURL()
        latestEnglishSRTURL = bestEnglishSRTURL()
        latestChineseSRTURL = bestChineseSRTURL()
    }

    func previewLaunchAssets() -> PreviewLaunchAssets? {
        syncLatestPreviewAssets()

        guard let sourceURL = latestSourceVideoURL else {
            alert(SubtitleError.missingSource.localizedDescription)
            return nil
        }
        guard let paths = derivedPaths() else {
            alert("Choose a source video and output folder first.")
            return nil
        }
        guard let englishSRTURL = latestEnglishSRTURL else {
            alert("Run English SRT first.")
            return nil
        }
        guard FileManager.default.fileExists(atPath: paths.mp4.path) else {
            alert("Generate English SRT first so the working MP4 exists.")
            return nil
        }

        let chineseSRTURL = latestChineseSRTURL
        return PreviewLaunchAssets(
            sourceURL: sourceURL,
            outputFolderURL: URL(fileURLWithPath: outputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
            previewMediaURL: paths.mp4,
            englishSRTURL: englishSRTURL,
            chineseSRTURL: chineseSRTURL,
            cueSourceURL: chineseSRTURL ?? englishSRTURL,
            cueSourceLabel: chineseSRTURL == nil ? "English" : "Chinese"
        )
    }

    func previewCues(from subtitleURL: URL, label: String) throws -> [SubtitlePreviewCue] {
        let cues = try SRTParser().parse(subtitleURL)
        guard !cues.isEmpty else {
            throw SubtitleError.emptySRT(label)
        }
        return try cues.map { try SubtitlePreviewCue.from($0) }
    }

    func showPreviewWindow(cues: [SubtitlePreviewCue], assets: PreviewLaunchAssets) {
        latestPreviewWindowController?.close()

        let controller = SubtitlePreviewWindowController(
            viewModel: SubtitlePreviewViewModel(cues: cues),
            previewURL: assets.previewMediaURL
        )
        controller.onRenderHighFidelityClip = { [weak self, weak controller] cue in
            self?.renderHighFidelityPreviewClip(
                cue: cue,
                assets: assets,
                controller: controller
            )
        }

        latestPreviewWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func renderHighFidelityPreviewClip(
        cue: SubtitlePreviewCue,
        assets: PreviewLaunchAssets,
        controller: SubtitlePreviewWindowController?
    ) {
        guard let chineseSRTURL = assets.chineseSRTURL else {
            alert("Chinese SRT is optional for preview browsing, but run Translate EN→ZH before rendering a localized preview clip.")
            return
        }

        startJob {
            self.syncRunnerPaths()
            let clipURL = try await self.runner.renderPreviewClip(
                source: assets.sourceURL,
                outputFolder: assets.outputFolderURL,
                cue: cue,
                enSRTOverride: assets.englishSRTURL.path,
                zhSRTOverride: chineseSRTURL.path
            )

            await MainActor.run {
                controller?.loadPreview(url: clipURL)
                controller?.showWindow(nil)
                controller?.window?.makeKeyAndOrderFront(nil)
                self.rememberOutput(
                    clipURL,
                    summary: "Preview clip ready. Review this excerpt for subtitle timing and layout."
                )
            }
        }
    }

    func updateWorkflowUI(progressStep: String? = nil) {
        let sourcePath = sourceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputPath = outputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = selectedProvider()
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let enURL = bestEnglishSRTURL()
        let zhURL = bestChineseSRTURL()
        let burnedURL = derivedPaths().map { FileManager.default.fileExists(atPath: $0.burned.path) ? $0.burned : nil } ?? nil

        if let progressStep {
            workflowCurrentLabel.stringValue = progressStep
            workflowNextLabel.stringValue = "Next: let this step finish, then review the generated file before moving on."
        } else if sourcePath.isEmpty {
            workflowCurrentLabel.stringValue = "Choose a source video."
            workflowNextLabel.stringValue = "Next: pick a .mov or .mp4 file to create the subtitle work folder."
        } else if outputPath.isEmpty {
            workflowCurrentLabel.stringValue = "Set an output folder."
            workflowNextLabel.stringValue = "Next: choose where the subtitle work folder and burned video should live."
        } else if enURL == nil {
            workflowCurrentLabel.stringValue = "Generate the English transcript."
            workflowNextLabel.stringValue = "Next: run English SRT, then open that file to fix wording or timing."
        } else if zhURL == nil {
            workflowCurrentLabel.stringValue = "Translate the English subtitles."
            workflowNextLabel.stringValue = apiKey.isEmpty
                ? "Next: enter your \(provider) API key, then run Translate EN→ZH."
                : "Next: run Translate EN→ZH, then open the Chinese SRT to polish the translation."
        } else if burnedURL == nil {
            workflowCurrentLabel.stringValue = "Burn bilingual subtitles into the video."
            workflowNextLabel.stringValue = "Next: run Merge ASS+Burn, then spot-check subtitle placement in the exported MP4."
        } else {
            workflowCurrentLabel.stringValue = "Everything is generated."
            workflowNextLabel.stringValue = "Next: open the burned video, or reopen the English / Chinese SRT files if you want another revision pass."
        }

        if lastOutputURL == nil {
            latestOutputTitleLabel.stringValue = burnedURL?.lastPathComponent ?? "No output yet"
            latestOutputPathLabel.stringValue = burnedURL?.path ?? "Run a step to generate subtitles or a burned video."
            if let burnedURL { lastOutputURL = burnedURL }
        }
        syncLatestPreviewAssets()
        updateOutputButtons()
    }

    func findTool(_ name: String) -> String {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return ""
    }

    func log(_ value: String) {
        DispatchQueue.main.async {
            let color: NSColor
            if value.contains("❌") || value.lowercased().contains("error") {
                color = NSColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1)
            } else if value.contains("✅") || value.lowercased().contains("done") {
                color = NSColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1)
            } else if value.contains("⚠️") {
                color = NSColor(red: 0.95, green: 0.75, blue: 0.2, alpha: 1)
            } else if value.contains("Translating") || value.contains("chunk") {
                color = NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1)
            } else {
                color = NSColor(red: 0.2, green: 0.85, blue: 0.5, alpha: 1)
            }
            let ts = { () -> String in
                let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
                return f.string(from: Date())
            }()
            let line = "[\(ts)] \(value)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: color
            ]
            self.logView.textStorage?.append(NSAttributedString(string: line + "\n", attributes: attrs))
            self.logView.scrollToEndOfDocument(nil)
        }
    }

    func alert(_ value: String) {
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = "Subtitle Burner"
            a.informativeText = value
            a.runModal()
        }
    }

    // MARK: - UI factory

// UI helpers moved to mkLabel/ghostButton/accentButton etc.
}

// MARK: - NSTableViewDataSource / Delegate (batch queue)

extension AppDelegate: NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return false }
        addToBatch(urls: items)
        return true
    }
}

extension AppDelegate: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { batchJobs.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let job = batchJobs[row]
        let cell = NSTextField(labelWithString: "")
        cell.lineBreakMode = .byTruncatingMiddle
        if tableColumn?.identifier.rawValue == "file" {
            cell.stringValue = job.sourceURL.lastPathComponent
        } else {
            switch job.status {
            case .queued:               cell.stringValue = "Queued"
            case .running(let step):    cell.stringValue = "⏳ \(step)"
            case .done:                 cell.stringValue = "✅ Done"
            case .failed(let msg):      cell.stringValue = "❌ \(msg)"
            case .cancelled:            cell.stringValue = "⚠️ Cancelled"
            }
        }
        return cell
    }
}

extension AppDelegate: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateWorkflowUI()
    }
}

// MARK: - Drag-and-drop (handled via NSWindow contentView registration above)
// AppDelegate handles drag via NSDraggingDestination on the scroll view

// MARK: - AssocKeys
private enum AssocKeys {
    static var statusDot:     UInt8 = 0
    static var statusText:    UInt8 = 1
    static var statusBar:     UInt8 = 2
    static var fileNameLabel: UInt8 = 3
    static var pendingBadge:  UInt8 = 4
}

// MARK: - Entry point

@main
struct SubtitleBurnerMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        MainActor.assumeIsolated {
            let delegate = AppDelegate()
            app.delegate = delegate
        }
        app.run()
    }
}
