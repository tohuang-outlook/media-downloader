import Foundation
import AppKit
import AVFoundation
import AVKit

public final class SubtitlePreviewViewModel {
    public let cues: [SubtitlePreviewCue]
    public private(set) var selectedCueIndex: Int?

    public init(cues: [SubtitlePreviewCue]) {
        self.cues = cues
        self.selectedCueIndex = cues.first?.index
    }

    public var selectedCue: SubtitlePreviewCue? {
        guard let selectedCueIndex else { return nil }
        return cues.first(where: { $0.index == selectedCueIndex })
    }

    public func selectCue(index: Int) {
        if cues.contains(where: { $0.index == index }) {
            selectedCueIndex = index
        }
    }
}

@MainActor
public final class SubtitlePreviewWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public let viewModel: SubtitlePreviewViewModel
    public var onRenderHighFidelityClip: ((SubtitlePreviewCue) -> Void)?

    private let playerView = AVPlayerView()
    private let cueTextField = NSTextField(labelWithString: "")
    private let cueTimeField = NSTextField(labelWithString: "")
    private let cueTableView = NSTableView()
    private let replayButton = NSButton(title: "-2s", target: nil, action: nil)
    private let forwardButton = NSButton(title: "+2s", target: nil, action: nil)
    private let renderButton = NSButton(title: "Render High-Fidelity Clip", target: nil, action: nil)

    public init(viewModel: SubtitlePreviewViewModel, previewURL: URL? = nil) {
        self.viewModel = viewModel
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Subtitle Preview"
        window.minSize = NSSize(width: 840, height: 520)
        super.init(window: window)

        configureWindow()

        if let previewURL {
            loadPreview(url: previewURL)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public func loadPreview(url: URL) {
        playerView.player = AVPlayer(url: url)
    }

    private func configureWindow() {
        guard let window else { return }

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        contentView.addSubview(splitView)

        let listContainer = makeCueListContainer()
        let detailContainer = makeDetailContainer()
        splitView.addArrangedSubview(listContainer)
        splitView.addArrangedSubview(detailContainer)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            listContainer.widthAnchor.constraint(equalToConstant: 320)
        ])

        if !viewModel.cues.isEmpty {
            cueTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        refreshSelection()
    }

    private func makeCueListContainer() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "Cues")
        header.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        header.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cue"))
        column.title = "Subtitle"
        cueTableView.addTableColumn(column)
        cueTableView.headerView = nil
        cueTableView.usesAlternatingRowBackgroundColors = true
        cueTableView.rowHeight = 44
        cueTableView.delegate = self
        cueTableView.dataSource = self
        scrollView.documentView = cueTableView

        container.addSubview(header)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeDetailContainer() -> NSView {
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.controlsStyle = .floating

        cueTextField.translatesAutoresizingMaskIntoConstraints = false
        cueTextField.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        cueTextField.lineBreakMode = .byWordWrapping
        cueTextField.maximumNumberOfLines = 0

        cueTimeField.translatesAutoresizingMaskIntoConstraints = false
        cueTimeField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        cueTimeField.textColor = .secondaryLabelColor

        replayButton.target = self
        replayButton.action = #selector(replayTwoSeconds)
        forwardButton.target = self
        forwardButton.action = #selector(skipForwardTwoSeconds)
        renderButton.target = self
        renderButton.action = #selector(renderHighFidelityClip)

        let buttonRow = NSStackView(views: [replayButton, forwardButton, renderButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12

        let stack = NSStackView(views: [playerView, cueTextField, cueTimeField, buttonRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(8, after: cueTextField)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            playerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320)
        ])

        return container
    }

    private func refreshSelection() {
        guard let cue = viewModel.selectedCue else {
            cueTextField.stringValue = "Select a subtitle cue to preview."
            cueTimeField.stringValue = ""
            replayButton.isEnabled = false
            forwardButton.isEnabled = false
            renderButton.isEnabled = false
            return
        }

        cueTextField.stringValue = cue.rawText
        cueTimeField.stringValue = "\(Self.format(seconds: cue.startSeconds)) - \(Self.format(seconds: cue.endSeconds))"
        replayButton.isEnabled = true
        forwardButton.isEnabled = true
        renderButton.isEnabled = true
    }

    private func seekPlayer(by deltaSeconds: Double) {
        guard let player = playerView.player else { return }
        let currentSeconds = player.currentTime().seconds
        let current = currentSeconds.isFinite ? currentSeconds : 0
        let target = max(0, current + deltaSeconds)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time)
    }

    private func seekToSelectedCue() {
        guard let cue = viewModel.selectedCue else { return }
        let cueStart = max(0, cue.startSeconds - 2.0)
        playerView.player?.seek(to: CMTime(seconds: cueStart, preferredTimescale: 600))
    }

    private static func format(seconds: Double) -> String {
        let totalMilliseconds = Int((seconds * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let wholeSeconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, wholeSeconds, milliseconds)
    }

    @objc
    private func replayTwoSeconds() {
        seekPlayer(by: -2.0)
    }

    @objc
    private func skipForwardTwoSeconds() {
        seekPlayer(by: 2.0)
    }

    @objc
    private func renderHighFidelityClip() {
        guard let cue = viewModel.selectedCue else { return }
        onRenderHighFidelityClip?(cue)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        viewModel.cues.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("CueCell")
        let textField: NSTextField

        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField = reused
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 2
            textField.font = NSFont.systemFont(ofSize: 13)
        }

        let cue = viewModel.cues[row]
        let summary = cue.rawText.replacingOccurrences(of: "\n", with: " / ")
        textField.stringValue = "\(cue.index). \(summary)"
        return textField
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = cueTableView.selectedRow
        guard row >= 0, row < viewModel.cues.count else { return }
        viewModel.selectCue(index: viewModel.cues[row].index)
        refreshSelection()
        seekToSelectedCue()
    }
}
