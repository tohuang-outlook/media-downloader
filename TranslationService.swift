import Foundation

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

public enum SubtitleError: LocalizedError, Equatable {
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
