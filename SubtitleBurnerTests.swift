import XCTest
@testable import SubtitleBurner   // adjust module name to match your Xcode target

// MARK: - SRTParser Tests

final class SRTParserTests: XCTestCase {

    let parser = SRTParser()

    func test_parsesStandardSRT() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,500
        Hello world

        2
        00:00:04,000 --> 00:00:06,000
        Second line
        """
        let cues = try parser.parse(string: srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Hello world")
        XCTAssertEqual(cues[0].start, "00:00:01,000")
        XCTAssertEqual(cues[0].end, "00:00:03,500")
        XCTAssertEqual(cues[1].text, "Second line")
    }

    func test_parsesMultiLineCue() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,000
        Line one
        Line two
        """
        let cues = try parser.parse(string: srt)
        XCTAssertEqual(cues[0].text, "Line one\nLine two")
    }

    func test_parsesWindowsLineEndings() throws {
        let srt = "1\r\n00:00:01,000 --> 00:00:02,000\r\nHello\r\n\r\n"
        let cues = try parser.parse(string: srt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Hello")
    }

    func test_emptyStringReturnsEmpty() throws {
        let cues = try parser.parse(string: "")
        XCTAssertTrue(cues.isEmpty)
    }

    func test_skipsBlocksWithoutTimestamp() throws {
        let srt = """
        just some text
        without arrow

        1
        00:00:01,000 --> 00:00:02,000
        Valid
        """
        let cues = try parser.parse(string: srt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Valid")
    }

    func test_parsesIndexFromBlock() throws {
        let srt = """
        42
        00:01:00,000 --> 00:01:05,000
        Text
        """
        let cues = try parser.parse(string: srt)
        XCTAssertEqual(cues[0].index, 42)
    }

    func test_handlesNoIndexLine() throws {
        // Some SRT files start directly with the timestamp
        let srt = "00:00:01,000 --> 00:00:02,000\nHello"
        let cues = try parser.parse(string: srt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Hello")
    }
}

// MARK: - SubtitlePreviewCore Tests

final class SubtitlePreviewCoreTests: XCTestCase {

    func test_previewCuePreservesCueTimingAndText() throws {
        let cue = Cue(index: 1, start: "00:00:01,000", end: "00:00:03,500", text: "Hello world")

        let previewCue = try SubtitlePreviewCue.from(cue)

        XCTAssertEqual(previewCue.id, "cue-1")
        XCTAssertEqual(previewCue.startSeconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(previewCue.endSeconds, 3.5, accuracy: 0.001)
        XCTAssertEqual(previewCue.rawText, "Hello world")
    }

    func test_previewViewModelSelectsCueByIndex() throws {
        let cues = [
            try SubtitlePreviewCue.from(
                Cue(index: 1, start: "00:00:01,000", end: "00:00:03,000", text: "First cue")
            ),
            try SubtitlePreviewCue.from(
                Cue(index: 2, start: "00:00:04,000", end: "00:00:06,000", text: "Second cue")
            )
        ]
        let model = SubtitlePreviewViewModel(cues: cues)

        model.selectCue(index: 2)

        XCTAssertEqual(model.selectedCue?.rawText, "Second cue")
    }

    func test_previewLineSplitterBalancesLongSingleLineCue() {
        let lines = SubtitlePreviewLineSplitter.split(
            "This is a longer subtitle that should be balanced for reading",
            maxCharactersPerLine: 24
        )

        XCTAssertEqual(lines, [
            "This is a longer",
            "subtitle that should be balanced for reading"
        ])
    }

    func test_previewClipJobUsesTwoSecondPaddingAroundCue() throws {
        let paths = Paths(
            source: URL(fileURLWithPath: "/tmp/demo.mov"),
            outputRoot: URL(fileURLWithPath: "/tmp/out")
        )
        let cue = try SubtitlePreviewCue.from(
            Cue(index: 7, start: "00:00:07,000", end: "00:00:09,000", text: "Preview me")
        )

        let job = PipelineRunner.makePreviewClipJob(paths: paths, cue: cue)

        XCTAssertEqual(job.startSeconds, 5.0, accuracy: 0.001)
        XCTAssertEqual(job.durationSeconds, 6.0, accuracy: 0.001)
        XCTAssertTrue(job.outputURL.lastPathComponent.contains("preview_5000_11000"))
    }

    func test_previewClipJobClampsWindowStartAtZero() throws {
        let paths = Paths(
            source: URL(fileURLWithPath: "/tmp/demo.mov"),
            outputRoot: URL(fileURLWithPath: "/tmp/out")
        )
        let cue = try SubtitlePreviewCue.from(
            Cue(index: 1, start: "00:00:01,000", end: "00:00:02,500", text: "Intro line")
        )

        let job = PipelineRunner.makePreviewClipJob(paths: paths, cue: cue)

        XCTAssertEqual(job.startSeconds, 0.0, accuracy: 0.001)
        XCTAssertEqual(job.durationSeconds, 4.5, accuracy: 0.001)
        XCTAssertTrue(job.outputURL.lastPathComponent.contains("preview_0_4500"))
    }

    func test_previewASSCuesClampAndShiftIntoClipLocalTimeline() throws {
        let clipJob = SubtitlePreviewClipJob(
            startSeconds: 5.0,
            durationSeconds: 6.0,
            outputURL: URL(fileURLWithPath: "/tmp/preview.mp4")
        )
        let cues = [
            Cue(index: 1, start: "00:00:04,000", end: "00:00:06,500", text: "Leading overlap"),
            Cue(index: 2, start: "00:00:07,000", end: "00:00:09,000", text: "Main cue"),
            Cue(index: 3, start: "00:00:10,500", end: "00:00:12,500", text: "Trailing overlap"),
            Cue(index: 4, start: "00:00:12,500", end: "00:00:13,000", text: "Outside clip")
        ]

        let previewCues = try PipelineRunner.makePreviewASSCues(from: cues, clipJob: clipJob)

        XCTAssertEqual(previewCues, [
            Cue(index: 1, start: "00:00:00,000", end: "00:00:01,500", text: "Leading overlap"),
            Cue(index: 2, start: "00:00:02,000", end: "00:00:04,000", text: "Main cue"),
            Cue(index: 3, start: "00:00:05,500", end: "00:00:06,000", text: "Trailing overlap")
        ])
    }

    func test_previewRenderSourcePrefersNormalizedMP4WhenPresent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("demo.mov")
        let outputRoot = root.appendingPathComponent("output", isDirectory: true)
        let paths = Paths(source: source, outputRoot: outputRoot)

        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data()))

        XCTAssertEqual(
            PipelineRunner.previewRenderSourceURL(source: source, paths: paths),
            source
        )

        XCTAssertTrue(FileManager.default.createFile(atPath: paths.mp4.path, contents: Data()))

        XCTAssertEqual(
            PipelineRunner.previewRenderSourceURL(source: source, paths: paths),
            paths.mp4
        )
    }
}

// MARK: - ASSTime Tests

final class ASSTimeTests: XCTestCase {

    func test_convertsSRTTimeToASS() {
        XCTAssertEqual(ASSTime.fromSRT("00:01:23,456"), "0:01:23.45")
    }

    func test_handlesHour() {
        XCTAssertEqual(ASSTime.fromSRT("01:00:00,000"), "1:00:00.00")
    }

    func test_trimsMillisecondsTo2Digits() {
        XCTAssertEqual(ASSTime.fromSRT("00:00:01,100"), "0:00:01.10")
    }

    func test_handlesZeroTime() {
        XCTAssertEqual(ASSTime.fromSRT("00:00:00,000"), "0:00:00.00")
    }
}

// MARK: - ASSEscape Tests

final class ASSEscapeTests: XCTestCase {

    func test_escapesBackslash() {
        XCTAssertEqual(ASSEscape.body("a\\b"), "a\\\\b")
    }

    func test_escapesBraces() {
        XCTAssertEqual(ASSEscape.body("{tag}"), "\\{tag\\}")
    }

    func test_escapesNewline() {
        XCTAssertEqual(ASSEscape.body("line1\nline2"), "line1\\Nline2")
    }

    func test_filterPathEscapesColon() {
        XCTAssertEqual(ASSEscape.filterPath("/path/to:file"), "/path/to\\:file")
    }

    func test_filterPathEscapesSingleQuote() {
        XCTAssertEqual(ASSEscape.filterPath("/path/it's"), "/path/it\\'s")
    }

    func test_filterPathEscapesComma() {
        XCTAssertEqual(ASSEscape.filterPath("a,b"), "a\\,b")
    }
}

// MARK: - ASSWriter Tests

final class ASSWriterTests: XCTestCase {

    func test_writesASSFile() throws {
        let zh = [Cue(index: 1, start: "00:00:01,000", end: "00:00:03,000", text: "你好")]
        let en = [Cue(index: 1, start: "00:00:01,000", end: "00:00:03,000", text: "Hello")]
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ass")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ASSWriter().write(zhCues: zh, enCues: en, to: tmp, width: 1920, height: 1080)

        let contents = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(contents.contains("[Script Info]"))
        XCTAssertTrue(contents.contains("PlayResX: 1920"))
        XCTAssertTrue(contents.contains("你好"))
        XCTAssertTrue(contents.contains("Hello"))
        XCTAssertTrue(contents.contains("Dialogue:"))
    }

    func test_throwsOnEmptyChineseCues() {
        XCTAssertThrowsError(
            try ASSWriter().write(zhCues: [], enCues: [], to: URL(fileURLWithPath: "/tmp/x.ass"),
                                  width: 1920, height: 1080)
        ) { error in
            XCTAssertTrue((error as? SubtitleError) == .emptySRT("Chinese"))
        }
    }

    func test_missingEnglishCueFallsBackToEmpty() throws {
        let zh = [Cue(index: 1, start: "00:00:01,000", end: "00:00:02,000", text: "你好")]
        let en: [Cue] = []  // deliberately empty
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ass")
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertNoThrow(try ASSWriter().write(zhCues: zh, enCues: en, to: tmp, width: 1920, height: 1080))
    }
}

// MARK: - Settings Tests

final class SettingsTests: XCTestCase {

    func test_defaultOutputFolder() {
        // Just verify it returns a non-empty string
        XCTAssertFalse(Settings.outputFolder.isEmpty)
    }

    func test_defaultModelForOpenAI() {
        XCTAssertEqual(Settings.defaultModel(for: "OpenAI"), "gpt-4.1-mini")
    }

    func test_defaultModelForDeepSeek() {
        XCTAssertEqual(Settings.defaultModel(for: "DeepSeek"), "deepseek-chat")
    }

    func test_defaultModelForGemini() {
        XCTAssertEqual(Settings.defaultModel(for: "Google Gemini"), "gemini-2.5-flash")
    }

    func test_roundTripWhisperModel() {
        Settings.whisperModel = "large-v3"
        XCTAssertEqual(Settings.whisperModel, "large-v3")
        Settings.whisperModel = "turbo"   // restore default
    }
}

// MARK: - KeychainStore Tests

final class KeychainStoreTests: XCTestCase {

    let testProvider = "TestProvider-\(UUID().uuidString)"

    override func tearDown() {
        KeychainStore.delete(for: testProvider)
    }

    func test_saveAndLoad() {
        KeychainStore.save(key: "sk-test-1234", for: testProvider)
        let loaded = KeychainStore.load(for: testProvider)
        XCTAssertEqual(loaded, "sk-test-1234")
    }

    func test_overwrite() {
        KeychainStore.save(key: "first", for: testProvider)
        KeychainStore.save(key: "second", for: testProvider)
        XCTAssertEqual(KeychainStore.load(for: testProvider), "second")
    }

    func test_deleteRemovesKey() {
        KeychainStore.save(key: "toDelete", for: testProvider)
        KeychainStore.delete(for: testProvider)
        XCTAssertNil(KeychainStore.load(for: testProvider))
    }

    func test_loadNonexistentReturnsNil() {
        XCTAssertNil(KeychainStore.load(for: "Provider-\(UUID().uuidString)"))
    }
}
