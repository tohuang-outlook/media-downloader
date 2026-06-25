import Foundation
import AppKit
import Combine

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

public struct PipelineProgress {
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
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: paths.mp4.path) {
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

@MainActor
public final class PipelineRunner: ObservableObject {

    // Callbacks set by AppDelegate / UI
    public var onLog: (String) -> Void = { _ in }
    public var onProgress: (PipelineProgress) -> Void = { _ in }

    private var cancellationToken = CancellationToken()
    private var activeProcess: Process?

    // Tool paths (populated by AppDelegate from Settings + UI fields)
    public var ffmpegPath: String  = ""
    public var ffprobePath: String = ""
    public var whisperPath: String = ""
    public var fontPath: String    = ""

    public init() {}

    // MARK: - Cancellation

    public func cancel() {
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
        try await run([ffmpegPath, "-y", "-i", paths.mp4.path,
                       "-vn", "-acodec", "pcm_s16le", "-ar", "16000", paths.wav.path])

        progress("Running Whisper transcription…", 0.35)
        try checkCancelled()
        try await run([whisperPath, paths.wav.path,
                       "--model", whisperModel,
                       "--language", "en",
                       "--task", "transcribe",
                       "--output_format", "srt",
                       "--output_dir", paths.root.path])

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

        guard FileManager.default.fileExists(atPath: paths.mp4.path) else {
            throw SubtitleError.missingFile(paths.mp4.path)
        }
        let assURL = try writeASSFile(
            videoURL: paths.mp4,
            paths: paths,
            enSRTOverride: enSRTOverride,
            zhSRTOverride: zhSRTOverride
        )

        progress("Burning subtitles into video…", 0.15)
        try checkCancelled()
        let filter = try makeASSFilter(for: assURL)
        try await run([ffmpegPath, "-y", "-i", paths.mp4.path,
                       "-vf", filter,
                       "-c:v", "libx264", "-preset", "fast", "-crf", "22",
                       "-c:a", "aac", "-b:a", "160k",
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
                Task { @MainActor [weak self] in
                    self?.log(s)
                }
                // Parse ffmpeg progress: "frame= 123 fps= 24 ... time=00:00:12.34"
                if let time = Self.parseFFmpegTime(s) {
                    DispatchQueue.main.async {
                        self?.onProgress(PipelineProgress(step: "Encoding…", fraction: -1, ffmpegTime: time))
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

    private func writeASSFile(
        videoURL: URL,
        paths: Paths,
        enSRTOverride: String,
        zhSRTOverride: String
    ) throws -> URL {
        let subtitleURLs = try resolveSubtitleURLs(
            paths: paths,
            enSRTOverride: enSRTOverride,
            zhSRTOverride: zhSRTOverride
        )
        let fontPath = try validatedFontPath()

        progress("Reading video resolution…", 0.05)
        let size = videoSize(videoURL)
        log("Video resolution: \(Int(size.width))×\(Int(size.height))")

        progress("Writing ASS subtitles…", 0.1)
        try checkCancelled()
        let parser = SRTParser()
        let zhCues = try parser.parse(subtitleURLs.zh)
        let enCues = try parser.parse(subtitleURLs.en)
        let writer = ASSWriter()
        try writer.write(
            zhCues: zhCues,
            enCues: enCues,
            to: paths.ass,
            width: Int(size.width),
            height: Int(size.height)
        )
        log("Font: \(fontPath)")
        log("ASS: \(paths.ass.path)")
        return paths.ass
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
        let fontPath = try validatedFontPath()
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
        log("Font: \(fontPath)")
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

    private func checkCancelled() throws {
        if cancellationToken.isCancelled { throw SubtitleError.cancelled }
    }

    private func progress(_ step: String, _ fraction: Double) {
        log(step)
        onProgress(PipelineProgress(step: step, fraction: fraction))
    }

    private func log(_ msg: String) {
        DispatchQueue.main.async { self.onLog(msg) }
    }

    nonisolated private static func parseFFmpegTime(_ line: String) -> String? {
        guard line.contains("time=") else { return nil }
        let parts = line.components(separatedBy: "time=")
        guard parts.count > 1 else { return nil }
        let time = parts[1].components(separatedBy: " ")[0]
        return time.hasPrefix("-") ? nil : time
    }

    nonisolated private static func formatFFmpegSeconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    nonisolated private static func srtTimestamp(fromSeconds value: Double) -> String {
        let milliseconds = max(0, Int((value * 1000).rounded()))
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let seconds = (milliseconds / 1_000) % 60
        let millis = milliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }
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
