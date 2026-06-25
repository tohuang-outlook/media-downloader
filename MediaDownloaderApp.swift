// MediaDownloaderApp.swift
// Dark workstation UI: deep purple + dark gray, two-column layout,
// settings panel left, terminal log right, status bar top-right.

import AppKit
import Foundation

// MARK: - Design tokens

extension NSColor {
    static let wsBackground  = NSColor(red: 0.09, green: 0.09, blue: 0.13, alpha: 1) // near-black bg
    static let wsPanel       = NSColor(red: 0.12, green: 0.11, blue: 0.17, alpha: 1) // card bg
    static let wsPanelBorder = NSColor(red: 0.25, green: 0.22, blue: 0.35, alpha: 1) // subtle border
    static let wsSection     = NSColor(red: 0.15, green: 0.14, blue: 0.21, alpha: 1) // inner section
    static let wsAccent      = NSColor(red: 0.52, green: 0.30, blue: 0.95, alpha: 1) // bright purple
    static let wsAccent2     = NSColor(red: 0.35, green: 0.22, blue: 0.80, alpha: 1) // deeper purple
    static let wsGreen       = NSColor(red: 0.20, green: 0.85, blue: 0.45, alpha: 1) // terminal green
    static let wsYellow      = NSColor(red: 0.95, green: 0.78, blue: 0.20, alpha: 1) // warning
    static let wsRed         = NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1) // error
    static let wsText        = NSColor(red: 0.90, green: 0.88, blue: 0.95, alpha: 1) // primary text
    static let wsSubtext     = NSColor(red: 0.50, green: 0.48, blue: 0.60, alpha: 1) // muted text
    static let wsFieldBg     = NSColor(red: 0.10, green: 0.09, blue: 0.15, alpha: 1) // input bg
    static let wsFieldBorder = NSColor(red: 0.28, green: 0.24, blue: 0.42, alpha: 1) // input border
    static let wsLogBg       = NSColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1) // log bg
    static let wsHighlight   = NSColor(red: 0.52, green: 0.30, blue: 0.95, alpha: 0.15) // selection
}

// MARK: - Prefs

private enum Prefs {
    static let outputFolder  = "md.outputFolder"
    static let ytdlpPath     = "md.ytdlpPath"
    static let galleryDLPath = "md.galleryDLPath"
    static let ffmpegPath    = "md.ffmpegPath"
    static let format        = "md.format"
    static let downloadSize  = "md.downloadSize"
    static let convertSize   = "md.convertSize"
    static let cookies       = "md.cookies"
    static let urlHistory    = "md.urlHistory"
}

// MARK: - Custom views

/// Solid dark panel with border
final class DarkPanel: NSView {
    var cornerRadius: CGFloat = 10
    var fillColor   = NSColor.wsPanel
    var borderColor = NSColor.wsPanelBorder

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill(); path.fill()
        borderColor.setStroke(); path.lineWidth = 1; path.stroke()
    }
    override var isOpaque: Bool { false }
}

/// Accent pill / format tile
final class AccentTile: NSButton {
    var isSelected = false { didSet { needsDisplay = true } }
    private let icon: String
    private let lbl: String

    init(icon: String, label: String) {
        self.icon = icon; self.lbl = label
        super.init(frame: .zero)
        title = ""; isBordered = false; wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        if isSelected {
            NSColor.wsAccent.withAlphaComponent(0.20).setFill(); path.fill()
            NSColor.wsAccent.setStroke(); path.lineWidth = 1.5; path.stroke()
        } else {
            NSColor.wsSection.setFill(); path.fill()
            NSColor.wsPanelBorder.setStroke(); path.lineWidth = 1; path.stroke()
        }

        let iconColor  = isSelected ? NSColor.wsAccent : NSColor.wsSubtext
        let labelColor = isSelected ? NSColor.wsText   : NSColor.wsSubtext

        let iAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: iconColor]
        let lAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: isSelected ? .semibold : .regular),
            .foregroundColor: labelColor
        ]
        let iStr = NSAttributedString(string: icon, attributes: iAttr)
        let lStr = NSAttributedString(string: lbl,  attributes: lAttr)
        let iSz = iStr.size(); let lSz = lStr.size()
        let totalH = iSz.height + 3 + lSz.height
        let y0 = (bounds.height - totalH) / 2
        lStr.draw(at: NSPoint(x: (bounds.width - lSz.width)/2, y: y0))
        iStr.draw(at: NSPoint(x: (bounds.width - iSz.width)/2, y: y0 + lSz.height + 3))
    }
    override var intrinsicContentSize: NSSize { NSSize(width: 90, height: 68) }
}

/// Pill toggle (size selector)
final class PillToggle: NSButton {
    var isSelected = false { didSet { needsDisplay = true } }
    init(label: String) {
        super.init(frame: .zero); title = label; isBordered = false; wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height/2, yRadius: bounds.height/2)
        if isSelected {
            NSColor.wsAccent.setFill(); path.fill()
        } else {
            NSColor.wsSection.setFill(); path.fill()
            NSColor.wsPanelBorder.setStroke(); path.lineWidth = 1; path.stroke()
        }
        let color = isSelected ? NSColor.white : NSColor.wsSubtext
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: isSelected ? .semibold : .regular),
            .foregroundColor: color
        ]
        let s = NSAttributedString(string: title, attributes: attr)
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width)/2, y: (bounds.height - sz.height)/2))
    }
    override var intrinsicContentSize: NSSize {
        let w = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15)]).width
        return NSSize(width: w + 22, height: 26)
    }
}

/// Primary action button with gradient
final class PrimaryButton: NSButton {
    var isRunning = false { didSet { needsDisplay = true } }
    override init(frame: NSRect) { super.init(frame: frame); isBordered = false; wantsLayer = true }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSGraphicsContext.current?.cgContext.saveGState()
        path.addClip()
        let grad = NSGradient(colors: [NSColor.wsAccent, NSColor.wsAccent2])
        grad?.draw(in: bounds, angle: 135)
        NSGraphicsContext.current?.cgContext.restoreGState()

        // Subtle top highlight
        let highlight = NSBezierPath(roundedRect: NSRect(x: 1, y: bounds.height-2, width: bounds.width-2, height: 1),
                                     xRadius: 0, yRadius: 0)
        NSColor(white: 1, alpha: 0.12).setFill(); highlight.fill()

        if isRunning {
            // Spinner text
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let s = NSAttributedString(string: "⏳  Processing…", attributes: attr)
            let sz = s.size()
            s.draw(at: NSPoint(x: (bounds.width - sz.width)/2, y: (bounds.height - sz.height)/2))
        } else {
            let labelText = "Start Download"
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let labelStr = NSAttributedString(string: labelText, attributes: attr)
            let labelSz  = labelStr.size()
            let startX = (bounds.width - labelSz.width) / 2
            let midY   = bounds.height / 2

            labelStr.draw(at: NSPoint(x: startX, y: midY - labelSz.height / 2))
        }
    }
}

/// Danger / secondary button
final class SecondaryButton: NSButton {
    init(label: String, action: Selector, target: AnyObject) {
        super.init(frame: .zero)
        title = label; self.target = target; self.action = action
        isBordered = false; wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 0.15).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 0.40).cgColor
        contentTintColor = NSColor.wsRed
        font = .systemFont(ofSize: 15, weight: .medium)
    }
    required init?(coder: NSCoder) { nil }
}

final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - AppDelegate

final class MediaDownloaderDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    // Left panel
    var urlCombo        = NSComboBox()
    var outputField     = NSTextField()
    var formatTiles:    [AccentTile]   = []
    var downloadPills:  [PillToggle]   = []
    var convertPills:   [PillToggle]   = []
    var customWidthField = NSTextField()
    var customWidthGroup = NSStackView()
    var igIndexesField  = NSTextField()
    var igIndexesGroup  = NSStackView()
    var advancedStateLabel = NSTextField(labelWithString: "No extra options for this selection.")
    var sourceGuidanceLabel = NSTextField(labelWithString: "Paste a YouTube or Instagram URL and I will suggest the best mode.")
    var cookiesPopup    = NSPopUpButton()
    var ytdlpField      = NSTextField()
    var galleryDLField  = NSTextField()
    var ffmpegField     = NSTextField()
    var toolsStack      = NSStackView()
    var toolsExpanded   = false
    var toolsChevron    = NSTextField(labelWithString: "›")

    // Right panel
    var logView         = NSTextView()
    var statusDot       = NSTextField(labelWithString: "●")
    var statusLabel     = NSTextField(labelWithString: "Idle")
    var outputFileLabel = NSTextField(labelWithString: "—")
    var outputSectionLabel = NSTextField(labelWithString: "No recent output yet")
    var outputActionHintLabel = NSTextField(labelWithString: "When a download finishes, you can open it here right away.")
    var elapsedLabel    = NSTextField(labelWithString: "")
    var progressBar     = NSProgressIndicator()
    var openOutputBtn   = NSButton()
    var revealOutputBtn = NSButton()
    var copyPathBtn     = NSButton()

    // Action buttons
    var downloadBtn     = PrimaryButton()
    var cancelBtn: NSButton!

    // State
    var running         = false
    var activeProcess:  Process?
    var lastOutputURL:  URL?
    var urlHistory:     [String] = []
    var selectedFormat  = 0
    var selectedDLSize  = 0
    var selectedCvSize  = 0
    var startTime:      Date?
    var elapsedTimer:   Timer?

    let formatDefs  = [("🎬","YT Video"),("🎵","YT Audio"),("📹","IG Video"),("🖼","IG Photo")]
    let sizeDefs    = ["Best","1080p","720p","480p","360p"]
    let convertDefs = ["No conversion","1080p","720p","480p","360p","Custom width"]

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ n: Notification) { buildUI(); restorePrefs(); refreshUIState() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    // MARK: - Build UI

    func buildUI() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "MediaDownloader"
        window.backgroundColor = NSColor.wsBackground
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.minSize = NSSize(width: 920, height: 650)

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(root)
        pin(root, to: window.contentView!)

        // ── Title bar area ────────────────────────────────────────────
        let titleBar = NSView()
        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = NSColor(red: 0.10, green: 0.09, blue: 0.15, alpha: 1).cgColor
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleBar)

        let appIcon = label("⬇", size: 16, color: .wsAccent)
        let appTitle = label("MediaDownloader", size: 14, weight: .bold, color: .wsText)
        let appSub   = label("macOS Edition", size: 10, color: .wsSubtext)

        statusDot.font = .systemFont(ofSize: 15)
        statusDot.textColor = .wsGreen
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = .wsSubtext

        let elapsedIcon = label("⏱", size: 10, color: .wsSubtext)
        elapsedLabel.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        elapsedLabel.textColor = .wsSubtext
        elapsedLabel.stringValue = "00:00"

        let leftTitle = hstack(spacing: 8, views: [appIcon, appTitle, appSub])
        let rightStatus = hstack(spacing: 12, views: [
            hstack(spacing: 4, views: [statusDot, statusLabel]),
            hstack(spacing: 4, views: [elapsedIcon, elapsedLabel])
        ])

        leftTitle.translatesAutoresizingMaskIntoConstraints = false
        rightStatus.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(leftTitle); titleBar.addSubview(rightStatus)
        NSLayoutConstraint.activate([
            titleBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            titleBar.topAnchor.constraint(equalTo: root.topAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: 52),
            leftTitle.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 80),
            leftTitle.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            rightStatus.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -16),
            rightStatus.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor)
        ])

        // Divider
        let titleDivider = NSBox(); titleDivider.boxType = .separator
        titleDivider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleDivider)
        NSLayoutConstraint.activate([
            titleDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            titleDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            titleDivider.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            titleDivider.heightAnchor.constraint(equalToConstant: 1)
        ])

        // ── Two-column body ───────────────────────────────────────────
        let bodyDivider = NSBox(); bodyDivider.boxType = .separator
        bodyDivider.translatesAutoresizingMaskIntoConstraints = false

        let leftCol  = buildLeftColumn()
        let rightCol = buildRightColumn()

        leftCol.translatesAutoresizingMaskIntoConstraints = false
        rightCol.translatesAutoresizingMaskIntoConstraints = false
        bodyDivider.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(leftCol)
        root.addSubview(bodyDivider)
        root.addSubview(rightCol)

        NSLayoutConstraint.activate([
            leftCol.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            leftCol.topAnchor.constraint(equalTo: titleDivider.bottomAnchor),
            leftCol.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            leftCol.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.44),

            bodyDivider.leadingAnchor.constraint(equalTo: leftCol.trailingAnchor),
            bodyDivider.topAnchor.constraint(equalTo: titleDivider.bottomAnchor),
            bodyDivider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bodyDivider.widthAnchor.constraint(equalToConstant: 1),

            rightCol.leadingAnchor.constraint(equalTo: bodyDivider.trailingAnchor),
            rightCol.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            rightCol.topAnchor.constraint(equalTo: titleDivider.bottomAnchor),
            rightCol.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Left column

    func buildLeftColumn() -> NSScrollView {
        let content = FlippedContainerView()
        content.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // ── Source section ───────────────────────────────────────────
        stack.addArrangedSubview(sectionTitle("SOURCE"))

        urlCombo.isEditable = true
        urlCombo.hasVerticalScroller = true
        urlCombo.placeholderString = "YouTube or Instagram URL…"
        urlCombo.delegate = self
        styleField(urlCombo)
        urlCombo.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let pasteBtn = toolButton("Paste", #selector(pasteURL))
        let clearBtn = toolButton("✕", #selector(clearURL))
        clearBtn.widthAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(fillRow([urlCombo, pasteBtn, clearBtn]))

        outputField.placeholderString = "Output folder…"
        styleField(outputField)
        outputField.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let chooseBtn = toolButton("Browse", #selector(chooseOutput))
        stack.addArrangedSubview(fillRow([outputField, chooseBtn]))

        sourceGuidanceLabel.font = .systemFont(ofSize: 12)
        sourceGuidanceLabel.textColor = .wsSubtext
        sourceGuidanceLabel.lineBreakMode = .byWordWrapping
        sourceGuidanceLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(sourceGuidanceLabel)

        stack.addArrangedSubview(divider())

        // ── Format section ───────────────────────────────────────────
        stack.addArrangedSubview(sectionTitle("FORMAT"))
        let tileRow = NSStackView(); tileRow.orientation = .horizontal; tileRow.spacing = 8
        tileRow.distribution = .fillEqually
        for (i,(icon,lbl)) in formatDefs.enumerated() {
            let t = AccentTile(icon: icon, label: lbl)
            t.target = self; t.action = #selector(formatTapped(_:)); t.tag = i
            t.isSelected = i == 0; formatTiles.append(t); tileRow.addArrangedSubview(t)
        }
        stack.addArrangedSubview(tileRow)

        stack.addArrangedSubview(divider())

        // ── Quality section ──────────────────────────────────────────
        stack.addArrangedSubview(sectionTitle("DOWNLOAD SIZE"))
        let dlRow = NSStackView(); dlRow.orientation = .horizontal; dlRow.spacing = 6
        for (i,s) in sizeDefs.enumerated() {
            let p = PillToggle(label: s); p.target = self; p.action = #selector(dlSizeTapped(_:))
            p.tag = i; p.isSelected = i == 0; downloadPills.append(p); dlRow.addArrangedSubview(p)
        }
        dlRow.addArrangedSubview(NSView()); stack.addArrangedSubview(dlRow)

        stack.addArrangedSubview(sectionTitle("CONVERT MP4 TO"))
        let cvRow = NSStackView(); cvRow.orientation = .horizontal; cvRow.spacing = 6
        for (i,s) in convertDefs.enumerated() {
            let p = PillToggle(label: s); p.target = self; p.action = #selector(cvSizeTapped(_:))
            p.tag = i; p.isSelected = i == 0; convertPills.append(p); cvRow.addArrangedSubview(p)
        }
        cvRow.addArrangedSubview(NSView()); stack.addArrangedSubview(cvRow)

        stack.addArrangedSubview(divider())

        // ── Advanced section ─────────────────────────────────────────
        stack.addArrangedSubview(sectionTitle("ADVANCED OPTIONS"))

        let advGrid = NSStackView(); advGrid.orientation = .vertical; advGrid.spacing = 10
        advGrid.alignment = .leading

        // Custom width
        customWidthGroup = vstack(spacing: 4, views: [microLabel("Custom Width"), customWidthField])
        customWidthField.placeholderString = "e.g. 1280"
        styleField(customWidthField)
        customWidthField.heightAnchor.constraint(equalToConstant: 42).isActive = true
        advGrid.addArrangedSubview(customWidthGroup)

        // IG indexes
        let listBtn = toolButton("List", #selector(listIGIndexes))
        listBtn.widthAnchor.constraint(equalToConstant: 54).isActive = true
        let igRow2  = fillRow([igIndexesField, listBtn])
        igIndexesField.placeholderString = "all, 1, 2-5"
        igIndexesField.stringValue = "all"
        styleField(igIndexesField)
        igIndexesField.heightAnchor.constraint(equalToConstant: 42).isActive = true
        igIndexesGroup = vstack(spacing: 4, views: [microLabel("IG Indexes"), igRow2])
        advGrid.addArrangedSubview(igIndexesGroup)
        igIndexesGroup.translatesAutoresizingMaskIntoConstraints = false
        igIndexesGroup.widthAnchor.constraint(equalTo: advGrid.widthAnchor).isActive = true
        igRow2.translatesAutoresizingMaskIntoConstraints = false
        igRow2.widthAnchor.constraint(equalTo: igIndexesGroup.widthAnchor).isActive = true
        igIndexesField.translatesAutoresizingMaskIntoConstraints = false
        igIndexesField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        igIndexesField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        advancedStateLabel.font = .systemFont(ofSize: 12)
        advancedStateLabel.textColor = .wsSubtext
        advGrid.addArrangedSubview(advancedStateLabel)

        stack.addArrangedSubview(advGrid)

        // Cookies
        stack.addArrangedSubview(microLabel("Browser Cookies"))
        cookiesPopup.addItems(withTitles: ["No cookies","Safari","Chrome","Firefox"])
        cookiesPopup.selectItem(withTitle: "Chrome")
        cookiesPopup.wantsLayer = true
        cookiesPopup.layer?.cornerRadius = 6
        stack.addArrangedSubview(cookiesPopup)

        stack.addArrangedSubview(divider())

        // ── Tools section (collapsible) ──────────────────────────────
        let toolsToggle = NSButton(title: "", target: self, action: #selector(toggleTools))
        toolsToggle.isBordered = false
        let toolsHeader = NSStackView(); toolsHeader.orientation = .horizontal; toolsHeader.spacing = 6
        toolsChevron.font = .systemFont(ofSize: 15); toolsChevron.textColor = .wsSubtext
        toolsHeader.addArrangedSubview(toolsChevron)
        toolsHeader.addArrangedSubview(sectionTitle("TOOL PATHS"))
        toolsHeader.addArrangedSubview(NSView())

        // make the row clickable
        let toolsClickRow = NSView()
        toolsClickRow.translatesAutoresizingMaskIntoConstraints = false
        toolsHeader.translatesAutoresizingMaskIntoConstraints = false
        toolsClickRow.addSubview(toolsHeader)
        pin(toolsHeader, to: toolsClickRow)
        toolsToggle.translatesAutoresizingMaskIntoConstraints = false
        toolsClickRow.addSubview(toolsToggle)
        pin(toolsToggle, to: toolsClickRow)
        stack.addArrangedSubview(toolsClickRow)

        toolsStack.orientation = .vertical; toolsStack.spacing = 10; toolsStack.isHidden = true
        toolsStack.alignment = .leading
        for (lbl, field, sel) in [
            ("yt-dlp", ytdlpField, #selector(chooseYTDLP)),
            ("gallery-dl", galleryDLField, #selector(chooseGalleryDL)),
            ("ffmpeg", ffmpegField, #selector(chooseFFmpeg))
        ] as [(String, NSTextField, Selector)] {
            styleField(field)
            field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            field.heightAnchor.constraint(equalToConstant: 40).isActive = true
            let findBtn = toolButton("Find", sel)
            // Use fillRow so field stretches like Source section does
            let toolRow = fillRow([field, findBtn])
            let lbl2 = microLabel(lbl)
            let col = NSStackView()
            col.orientation = .vertical
            col.spacing = 4
            col.alignment = .leading
            col.addArrangedSubview(lbl2)
            col.addArrangedSubview(toolRow)
            // Bind col and toolRow width to toolsStack width
            col.translatesAutoresizingMaskIntoConstraints = false
            toolsStack.addArrangedSubview(col)
        }
        let checkBtn = toolButton("Check Tools", #selector(checkTools))
        toolsStack.addArrangedSubview(checkBtn)
        stack.addArrangedSubview(toolsStack)
        // After adding to stack, bind toolsStack width to stack width
        toolsStack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(divider())

        // ── Download button ──────────────────────────────────────────
        downloadBtn.target = self; downloadBtn.action = #selector(download)
        downloadBtn.heightAnchor.constraint(equalToConstant: 50).isActive = true

        cancelBtn = SecondaryButton(label: "✕  Cancel", action: #selector(cancelDownload), target: self)
        cancelBtn.isHidden = true
        cancelBtn.heightAnchor.constraint(equalToConstant: 42).isActive = true

        progressBar.style = .bar; progressBar.isIndeterminate = true; progressBar.isHidden = true
        // controlTint deprecated on macOS 14+

        let actionStack = NSStackView(); actionStack.orientation = .vertical; actionStack.spacing = 8
        actionStack.addArrangedSubview(downloadBtn)
        actionStack.addArrangedSubview(cancelBtn)
        actionStack.addArrangedSubview(progressBar)
        stack.addArrangedSubview(actionStack)

        stack.addArrangedSubview(divider())

        outputFileLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        outputFileLabel.textColor = .wsText
        outputFileLabel.lineBreakMode = .byTruncatingMiddle
        outputSectionLabel.font = .systemFont(ofSize: 12)
        outputSectionLabel.textColor = .wsSubtext
        outputSectionLabel.lineBreakMode = .byTruncatingTail
        outputActionHintLabel.font = .systemFont(ofSize: 12)
        outputActionHintLabel.textColor = .wsSubtext
        outputActionHintLabel.lineBreakMode = .byWordWrapping
        outputActionHintLabel.maximumNumberOfLines = 0

        openOutputBtn = toolButton("Open File", #selector(openLastOutput))
        revealOutputBtn = toolButton("Reveal in Finder", #selector(revealLastOutput))
        copyPathBtn = toolButton("Copy Path", #selector(copyLastOutputPath))
        let outputActions = NSStackView()
        outputActions.orientation = .horizontal
        outputActions.spacing = 8
        outputActions.addArrangedSubview(openOutputBtn)
        outputActions.addArrangedSubview(revealOutputBtn)
        outputActions.addArrangedSubview(copyPathBtn)
        outputActions.addArrangedSubview(NSView())

        let latestOutput = NSStackView()
        latestOutput.orientation = .vertical
        latestOutput.spacing = 4
        latestOutput.alignment = .leading
        latestOutput.addArrangedSubview(sectionTitle("LATEST OUTPUT"))
        latestOutput.addArrangedSubview(outputFileLabel)
        latestOutput.addArrangedSubview(outputSectionLabel)
        latestOutput.addArrangedSubview(outputActions)
        latestOutput.addArrangedSubview(outputActionHintLabel)
        stack.addArrangedSubview(latestOutput)

        // Force actionStack and downloadBtn to fill full width
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        downloadBtn.translatesAutoresizingMaskIntoConstraints = false
        downloadBtn.widthAnchor.constraint(equalTo: actionStack.widthAnchor).isActive = true
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.widthAnchor.constraint(equalTo: actionStack.widthAnchor).isActive = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.widthAnchor.constraint(equalTo: actionStack.widthAnchor).isActive = true

        // Make stack fill width — including toolsStack and its children
        for view in stack.arrangedSubviews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }
        // Bind toolsStack children (tool rows) to same width
        for col in toolsStack.arrangedSubviews {
            col.translatesAutoresizingMaskIntoConstraints = false
            col.widthAnchor.constraint(equalTo: toolsStack.widthAnchor).isActive = true
            if let colStack = col as? NSStackView {
                for sub in colStack.arrangedSubviews {
                    if let rowStack = sub as? NSStackView {
                        rowStack.translatesAutoresizingMaskIntoConstraints = false
                        rowStack.widthAnchor.constraint(equalTo: colStack.widthAnchor).isActive = true
                    }
                }
            }
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        content.addSubview(stack)
        scrollView.documentView = content
        scrollView.contentView.backgroundColor = NSColor.wsBackground

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])

        return scrollView
    }

    // MARK: - Right column (log)

    func buildRightColumn() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.wsLogBg.cgColor

        // Log header
        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor(red: 0.09, green: 0.08, blue: 0.13, alpha: 1).cgColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let termTitle = label(">_  Process Log", size: 11, weight: .semibold, color: .wsSubtext)
        let clearBtn  = toolButton("Clear", #selector(clearLog))
        let copyBtn   = toolButton("Copy", #selector(copyLog))

        let headerInner = hstack(spacing: 8, views: [termTitle, NSView(), clearBtn, copyBtn])
        headerInner.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerInner)
        NSLayoutConstraint.activate([
            headerInner.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            headerInner.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            headerInner.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            header.heightAnchor.constraint(equalToConstant: 42)
        ])

        // Divider under header
        let hDiv = NSBox(); hDiv.boxType = .separator; hDiv.translatesAutoresizingMaskIntoConstraints = false

        // Log text view
        logView.isEditable = false
        logView.drawsBackground = false
        logView.backgroundColor = .clear
        logView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        logView.textColor = NSColor(red: 0.2, green: 0.85, blue: 0.45, alpha: 1)
        logView.textContainerInset = NSSize(width: 10, height: 10)

        let logScroll = NSScrollView()
        logScroll.drawsBackground = false
        logScroll.hasVerticalScroller = true
        logScroll.documentView = logView
        logScroll.contentView.backgroundColor = NSColor.wsLogBg
        logScroll.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(header)
        container.addSubview(hDiv)
        container.addSubview(logScroll)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.topAnchor),
            hDiv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hDiv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hDiv.topAnchor.constraint(equalTo: header.bottomAnchor),
            logScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            logScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            logScroll.topAnchor.constraint(equalTo: hDiv.bottomAnchor),
            logScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    // MARK: - UI helpers

    func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.textColor = color; return f
    }

    func sectionTitle(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 15, weight: .bold)
        f.textColor = .wsSubtext; return f
    }

    func microLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 13); f.textColor = .wsSubtext; return f
    }

    func divider() -> NSBox {
        let b = NSBox(); b.boxType = .separator
        b.heightAnchor.constraint(equalToConstant: 1).isActive = true; return b
    }

    func toolButton(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded; b.isBordered = false; b.wantsLayer = true
        b.layer?.backgroundColor = NSColor.wsSection.cgColor
        b.layer?.cornerRadius = 6
        b.layer?.borderWidth = 1
        b.layer?.borderColor = NSColor.wsFieldBorder.cgColor
        b.contentTintColor = .wsText
        b.font = .systemFont(ofSize: 15, weight: .medium)
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let w = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15)]).width
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: w + 18).isActive = true
        return b
    }

    func styleField(_ f: NSControl) {
        f.wantsLayer = true
        f.layer?.backgroundColor = NSColor.wsFieldBg.cgColor
        f.layer?.cornerRadius = 6
        f.layer?.borderWidth = 1
        f.layer?.borderColor = NSColor.wsFieldBorder.cgColor
        if let tf = f as? NSTextField {
            tf.textColor = .wsText; tf.isBordered = false; tf.drawsBackground = false
            tf.focusRingType = .none
            tf.font = .systemFont(ofSize: 14)
            if let cell = tf.cell as? NSTextFieldCell {
                cell.placeholderAttributedString = NSAttributedString(
                    string: tf.placeholderString ?? "",
                    attributes: [.foregroundColor: NSColor.wsSubtext,
                                 .font: NSFont.systemFont(ofSize: 14)]
                )
            }
        }
        if let cb = f as? NSComboBox {
            cb.textColor = .wsText; cb.isBordered = false; cb.drawsBackground = false
            cb.focusRingType = .none; cb.font = .systemFont(ofSize: 14)
        }
    }

    func hstack(spacing: CGFloat, views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = .horizontal; s.spacing = spacing; return s
    }

    func vstack(spacing: CGFloat, views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = .vertical; s.spacing = spacing
        s.alignment = .leading; return s
    }

    func fillRow(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = .horizontal; s.spacing = 6
        if let first = views.first { first.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        return s
    }

    func pin(_ child: NSView, to parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    // MARK: - Format / size selection

    @objc func formatTapped(_ s: AccentTile) { selectFormat(s.tag) }
    func selectFormat(_ i: Int) {
        selectedFormat = i
        formatTiles.forEach { $0.isSelected = $0.tag == i }
        refreshUIState()
    }

    @objc func dlSizeTapped(_ s: PillToggle) { selectDLSize(s.tag) }
    func selectDLSize(_ i: Int) { selectedDLSize = i; downloadPills.forEach { $0.isSelected = $0.tag == i } }

    @objc func cvSizeTapped(_ s: PillToggle) { selectCVSize(s.tag) }
    func selectCVSize(_ i: Int) {
        selectedCvSize = i
        convertPills.forEach { $0.isSelected = $0.tag == i }
        refreshUIState()
    }

    func refreshUIState() {
        let mode = formatDefs[selectedFormat].1
        let isIGMode = mode.hasPrefix("IG")
        let showCustomWidth = convertDefs[selectedCvSize] == "Custom width" && mode != "YT Audio"
        DispatchQueue.main.async {
            self.igIndexesGroup.isHidden = !isIGMode
            self.customWidthGroup.isHidden = !showCustomWidth
            self.advancedStateLabel.isHidden = isIGMode || showCustomWidth
            self.updateSourceGuidance()
            self.updateOutputActions()
        }
    }

    // MARK: - Actions

    @objc func pasteURL() {
        let s = NSPasteboard.general.string(forType: .string) ?? ""
        if !s.isEmpty {
            urlCombo.stringValue = s
            autoSelectModeIfHelpful(for: s)
        }
        updateSourceGuidance()
    }
    @objc func clearURL() {
        urlCombo.stringValue = ""
        updateSourceGuidance()
    }
    @objc func clearLog() { logView.textStorage?.setAttributedString(NSAttributedString(string: "")) }
    @objc func copyLog() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(logView.string, forType: .string) }

    @objc func toggleTools() {
        toolsExpanded.toggle()
        toolsChevron.stringValue = toolsExpanded ? "▾" : "›"
        toolsStack.isHidden = !toolsExpanded
    }

    @objc func chooseOutput() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        if p.runModal() == .OK, let u = p.url { outputField.stringValue = u.path; savePrefs(); updateOutputActions() }
    }
    @objc func chooseYTDLP()     { chooseFile(into: ytdlpField) }
    @objc func chooseGalleryDL() { chooseFile(into: galleryDLField) }
    @objc func chooseFFmpeg()    { chooseFile(into: ffmpegField) }
    func chooseFile(into f: NSTextField) {
        let p = NSOpenPanel(); if p.runModal() == .OK, let u = p.url { f.stringValue = u.path; savePrefs() }
    }

    @objc func cancelDownload() {
        activeProcess?.terminate(); activeProcess = nil; running = false
        setRunning(false); log("⚠️  Cancelled by user.")
    }

    @objc func checkTools() {
        start {
            for (name, path) in [("yt-dlp", self.ytdlpField.stringValue),
                                  ("gallery-dl", self.galleryDLField.stringValue),
                                  ("ffmpeg", self.ffmpegField.stringValue)] {
                let ok = FileManager.default.isExecutableFile(atPath: path)
                self.log("\(ok ? "✅" : "❌")  \(name)  →  \(path.isEmpty ? "not set" : path)")
                if ok, let ver = try? self.capture([path, "--version"]).trimmingCharacters(in: .whitespacesAndNewlines) {
                    self.log("    version: \(ver.split(whereSeparator: \.isNewline).first.map(String.init) ?? ver)")
                }
            }
        }
    }

    @objc func listIGIndexes() { start { try self.performListIGIndexes() } }
    @objc func download()      { start { try self.performDownload() } }

    // MARK: - Running state

    func setRunning(_ on: Bool) {
        DispatchQueue.main.async {
            self.downloadBtn.isRunning = on
            self.downloadBtn.isEnabled = !on
            self.cancelBtn.isHidden = !on
            self.progressBar.isHidden = !on
            if on { self.progressBar.startAnimation(nil) } else { self.progressBar.stopAnimation(nil) }
            self.statusDot.textColor   = on ? .wsYellow : .wsGreen
            self.statusLabel.stringValue = on ? "Running" : "Idle"
            if !on { self.elapsedTimer?.invalidate(); self.elapsedTimer = nil; self.elapsedLabel.stringValue = "00:00" }
        }
    }

    func start(_ work: @escaping () throws -> Void) {
        guard !running else { alert("A download is already running."); return }
        running = true; setRunning(true); savePrefs()
        startTime = Date()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.startTime else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            let m = elapsed / 60; let s = elapsed % 60
            DispatchQueue.main.async { self.elapsedLabel.stringValue = String(format: "%02d:%02d", m, s) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do { try work(); self.log("✅  Done.") }
            catch let e as NSError { self.log("❌  \(e.localizedDescription)"); self.alert(e.localizedDescription) }
            catch { self.log("❌  \(error.localizedDescription)") }
            self.running = false; self.setRunning(false)
        }
    }

    // MARK: - Prefs

    func restorePrefs() {
        let d = UserDefaults.standard
        outputField.stringValue    = d.string(forKey: Prefs.outputFolder)  ?? "\(NSHomeDirectory())/Downloads"
        ytdlpField.stringValue     = d.string(forKey: Prefs.ytdlpPath)     ?? findTool("yt-dlp")
        galleryDLField.stringValue = d.string(forKey: Prefs.galleryDLPath) ?? findTool("gallery-dl")
        ffmpegField.stringValue    = d.string(forKey: Prefs.ffmpegPath)    ?? findTool("ffmpeg")
        let savedCookies = d.string(forKey: Prefs.cookies) ?? "Chrome"
        cookiesPopup.selectItem(withTitle: savedCookies)
        urlHistory = d.stringArray(forKey: Prefs.urlHistory) ?? []
        urlCombo.removeAllItems(); urlCombo.addItems(withObjectValues: urlHistory)
        if let fmt = d.string(forKey: Prefs.format),
           let i = formatDefs.firstIndex(where: { $0.1 == fmt }) { selectFormat(i) }
        if let ds = d.string(forKey: Prefs.downloadSize),
           let i = sizeDefs.firstIndex(of: ds) { selectDLSize(i) }
        if let cs = d.string(forKey: Prefs.convertSize),
           let i = convertDefs.firstIndex(of: cs) { selectCVSize(i) }
        refreshUIState()
        updateSourceGuidance()
        updateOutputActions()
    }

    func savePrefs() {
        let d = UserDefaults.standard
        d.set(outputField.stringValue,    forKey: Prefs.outputFolder)
        d.set(ytdlpField.stringValue,     forKey: Prefs.ytdlpPath)
        d.set(galleryDLField.stringValue, forKey: Prefs.galleryDLPath)
        d.set(ffmpegField.stringValue,    forKey: Prefs.ffmpegPath)
        d.set(formatDefs[selectedFormat].1, forKey: Prefs.format)
        d.set(sizeDefs[selectedDLSize],    forKey: Prefs.downloadSize)
        d.set(convertDefs[selectedCvSize], forKey: Prefs.convertSize)
        d.set(cookiesPopup.titleOfSelectedItem ?? "Chrome", forKey: Prefs.cookies)
        d.set(urlHistory, forKey: Prefs.urlHistory)
    }

    func addURLToHistory(_ url: String) {
        urlHistory.removeAll { $0 == url }; urlHistory.insert(url, at: 0)
        if urlHistory.count > 20 { urlHistory = Array(urlHistory.prefix(20)) }
        DispatchQueue.main.async { self.urlCombo.removeAllItems(); self.urlCombo.addItems(withObjectValues: self.urlHistory) }
        savePrefs()
    }

    // MARK: - Download logic

    func performDownload() throws {
        let outputDir = URL(fileURLWithPath: outputField.stringValue.isEmpty
            ? "\(NSHomeDirectory())/Downloads" : outputField.stringValue)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let src = urlCombo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { throw message("Paste a URL first.") }
        addURLToHistory(src)
        let mode = formatDefs[selectedFormat].1
        if mode.hasPrefix("IG") { try requireInstagramCookies() }
        if ["IG Video","IG Photo"].contains(mode) {
            let files = try performIGDownload(sourceURL: src, outputDir: outputDir, mode: mode)
            if mode == "IG Video", convertDefs[selectedCvSize] != "No conversion" {
                for f in files { let c = try convertMP4(f); showOutput(c) }
            }
            return
        }
        let ytdlp = try requireTool(ytdlpField.stringValue, "yt-dlp")
        var args = [ytdlp,"--newline","--no-mtime","-P",outputDir.path,
                    "-o","%(title).180B [%(id)s].%(ext)s","--print","after_move:filepath"]
        args += cookieArgs()
        switch mode {
        case "YT Audio": args += ["-x","--audio-format","mp3","--audio-quality","0"]
        case "YT Video": args += ["--merge-output-format","mp4","-f",ytFormat()]
        default: throw message("Unknown format.")
        }
        args.append(src)
        let started = Date()
        let result  = try runCollecting(args)
        var files   = findFiles(in: result.lines)
        if files.isEmpty { files = recentFiles(in: outputDir, since: started, mode: mode) }
        guard let final = files.last else { throw message("Download finished but output not found.") }
        files.forEach { showOutput($0) }
        if mode == "YT Video", convertDefs[selectedCvSize] != "No conversion" {
            let c = try convertMP4(final); showOutput(c)
        }
    }

    func showOutput(_ url: URL) {
        log("📁  \(url.path)")
        lastOutputURL = url
        DispatchQueue.main.async {
            self.outputFileLabel.stringValue = url.lastPathComponent
            self.outputSectionLabel.stringValue = url.deletingLastPathComponent().path
            self.outputActionHintLabel.stringValue = "Download complete. Open the file now, reveal it in Finder, or copy its path."
            self.updateOutputActions()
        }
    }

    func updateOutputActions() {
        let hasOutput = lastOutputURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        openOutputBtn.isEnabled = hasOutput
        revealOutputBtn.isEnabled = hasOutput
        copyPathBtn.isEnabled = hasOutput
        if !hasOutput {
            outputActionHintLabel.stringValue = "When a download finishes, you can open it here right away."
        }
    }

    func updateSourceGuidance() {
        let raw = urlCombo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw.lowercased()), let host = url.host else {
            sourceGuidanceLabel.stringValue = raw.isEmpty
                ? "Paste a YouTube or Instagram URL and I will suggest the best mode."
                : "URL pasted. I will keep the current mode until the link is recognizable."
            return
        }

        let path = url.path
        let selected = formatDefs[selectedFormat].1
        if host.contains("youtube.com") || host.contains("youtu.be") {
            sourceGuidanceLabel.stringValue = selected == "YT Audio"
                ? "Detected YouTube. This mode will extract MP3 audio; switch back to YT Video if you want MP4."
                : "Detected YouTube. YT Video is the default fit here, and YT Audio is one click away for MP3."
            return
        }

        if host.contains("instagram.com") {
            if path.contains("/reel") || path.contains("/reels") || path.contains("/tv/") {
                sourceGuidanceLabel.stringValue = "Detected Instagram video content. IG Video is the right starting mode."
            } else if path.contains("/p/") {
                sourceGuidanceLabel.stringValue = "Detected an Instagram post. IG Video is preselected; switch to IG Photo for image-only items and use List to inspect carousel indexes."
            } else {
                sourceGuidanceLabel.stringValue = "Detected Instagram. IG Video or IG Photo will work depending on what the post contains."
            }
            return
        }

        sourceGuidanceLabel.stringValue = "Link recognized, but this app is tuned for YouTube and Instagram URLs."
    }

    func autoSelectModeIfHelpful(for raw: String) {
        guard let url = URL(string: raw.lowercased()), let host = url.host else { return }
        let path = url.path
        if host.contains("youtube.com") || host.contains("youtu.be") {
            if formatDefs[selectedFormat].1.hasPrefix("IG") { selectFormat(0) }
            return
        }
        if host.contains("instagram.com") {
            if path.contains("/reel") || path.contains("/reels") || path.contains("/tv/") {
                selectFormat(2)
            } else if path.contains("/p/"), !formatDefs[selectedFormat].1.hasPrefix("IG") {
                selectFormat(2)
            }
        }
    }

    @objc func openLastOutput() {
        guard let url = lastOutputURL, FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func revealLastOutput() {
        guard let url = lastOutputURL, FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func copyLastOutputPath() {
        guard let url = lastOutputURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        outputActionHintLabel.stringValue = "Output path copied. You can paste it into Finder, Terminal, or another app."
    }

    func performIGDownload(sourceURL: String, outputDir: URL, mode: String) throws -> [URL] {
        let gd = try requireTool(galleryDLField.stringValue, "gallery-dl")
        let filter = mode == "IG Video" ? "video_url is not None" : "video_url is None"
        var all: [URL] = []; var seen = Set<String>()
        for range in igRanges() {
            var args = [gd,"--no-mtime","-D",outputDir.path,"--Print","after:{_path}"]
            args += cookieArgs() + ["--filter", filter]
            if let r = range { args += ["--range", r] }
            args.append(sourceURL)
            let started = Date()
            let result  = try runCollecting(args)
            var files   = findFiles(in: result.lines)
            if files.isEmpty { files = recentFiles(in: outputDir, since: started, mode: mode) }
            for f in files where !seen.contains(f.path) { seen.insert(f.path); all.append(f) }
        }
        guard !all.isEmpty else { throw message("No files found. Check IG indexes and cookies.") }
        all.forEach { showOutput($0) }
        return all
    }

    func performListIGIndexes() throws {
        let ytdlp = try requireTool(ytdlpField.stringValue, "yt-dlp")
        let src   = urlCombo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { throw message("Paste an Instagram URL first.") }
        let args  = [ytdlp,"--ignore-errors","--flat-playlist","--print",
                     "%(playlist_index)s/%(playlist_count)s %(id)s %(title)s"] + cookieArgs() + [src]
        let result = try runCollecting(args, allowFailure: true)
        let parsed = result.lines
            .filter { $0.range(of: #"^\d+/\d+"#, options: .regularExpression) != nil }
            .compactMap(parseIdx)
        if let total = parsed.map(\.total).max() {
            let vids   = parsed.map(\.index).sorted()
            let photos = Array(Set(1...total).subtracting(vids)).sorted()
            log("Carousel: \(total) items")
            if !vids.isEmpty   { log("  Videos  → \(vids.map(String.init).joined(separator: ","))") }
            if !photos.isEmpty { log("  Photos  → \(photos.map(String.init).joined(separator: ","))") }
        } else { log("Could not detect index count.") }
    }

    func convertMP4(_ input: URL) throws -> URL {
        let ff  = try requireTool(ffmpegField.stringValue, "ffmpeg")
        let cvs = convertDefs[selectedCvSize]
        let scale: String; let suffix: String
        switch cvs {
        case "1080p": scale = "scale=-2:1080"; suffix = "1080p"
        case "720p":  scale = "scale=-2:720";  suffix = "720p"
        case "480p":  scale = "scale=-2:480";  suffix = "480p"
        case "360p":  scale = "scale=-2:360";  suffix = "360p"
        case "Custom width":
            let widthText = customWidthField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let width = Int(widthText), width > 0 else {
                throw message("Enter a positive custom width, for example 1280.")
            }
            scale = "scale=\(width):-2"; suffix = "w\(width)"
        default: return input
        }
        let out = input.deletingLastPathComponent()
            .appendingPathComponent("\(input.deletingPathExtension().lastPathComponent)_\(suffix).mp4")
        try run([ff,"-y","-i",input.path,"-vf",scale,"-c:v","libx264","-preset","fast","-crf","22",
                 "-c:a","aac","-b:a","160k",out.path])
        return out
    }

    func ytFormat() -> String {
        switch sizeDefs[selectedDLSize] {
        case "1080p": return "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/best[height<=1080]"
        case "720p":  return "bv*[height<=720][ext=mp4]+ba[ext=m4a]/best[height<=720]"
        case "480p":  return "bv*[height<=480][ext=mp4]+ba[ext=m4a]/best[height<=480]"
        case "360p":  return "bv*[height<=360][ext=mp4]+ba[ext=m4a]/best[height<=360]"
        default:      return "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/best"
        }
    }

    func cookieArgs() -> [String] {
        switch cookiesPopup.titleOfSelectedItem ?? "" {
        case "Safari":  return ["--cookies-from-browser","safari"]
        case "Chrome":  return ["--cookies-from-browser","chrome"]
        case "Firefox": return ["--cookies-from-browser","firefox"]
        default: return []
        }
    }

    func requireInstagramCookies() throws {
        guard !cookieArgs().isEmpty else { throw message("Instagram requires browser cookies. Select Safari/Chrome/Firefox.") }
    }

    func igRanges() -> [String?] {
        let raw = igIndexesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.lowercased() != "all" else { return [nil] }
        return raw.split(separator: ",").map { Optional(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func findFiles(in lines: [String]) -> [URL] {
        var files: [URL] = []; var seen = Set<String>()
        for line in lines {
            for c in pathCandidates(from: line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if FileManager.default.fileExists(atPath: c), !seen.contains(c) {
                    seen.insert(c); files.append(URL(fileURLWithPath: c))
                }
            }
        }
        return files
    }

    func pathCandidates(from line: String) -> [String] {
        var c: [String] = []
        if line.hasPrefix("/") { c.append(line) }
        for m in [" to: "," Destination: "," Merging formats into "] {
            if let r = line.range(of: m) {
                let p = String(line[r.upperBound...]).trimmingCharacters(in: .init(charactersIn: " \"'"))
                if p.hasPrefix("/") { c.append(p) }
            }
        }
        return c
    }

    func recentFiles(in dir: URL, since date: Date, mode: String) -> [URL] {
        let exts: Set<String>
        switch mode {
        case "IG Photo": exts = ["jpg","jpeg","png","webp","heic","avif"]
        case "YT Audio": exts = ["mp3","m4a","opus","wav"]
        default:         exts = ["mp4","m4v","mov","webm","mkv"]
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
        else { return [] }
        return urls.compactMap { url -> (URL, Date)? in
            guard exts.contains(url.pathExtension.lowercased()),
                  let v = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mod = v.contentModificationDate, mod >= date.addingTimeInterval(-5) else { return nil }
            return (url, mod)
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    func run(_ args: [String]) throws {
        if try runCollecting(args).status != 0 { throw message("Command failed: \(args[0])") }
    }

    func runCollecting(_ args: [String], allowFailure: Bool = false) throws -> (status: Int32, lines: [String]) {
        let ts = timestamp()
        log("[\(ts)]  $ \(args.joined(separator: " "))")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        var lines: [String] = []; let lock = NSLock()
        try p.run(); activeProcess = p
        pipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let split = text.split(whereSeparator: \.isNewline).map(String.init)
            lock.lock(); lines.append(contentsOf: split); lock.unlock()
            split.forEach { self.log("[\(self.timestamp())]  \($0)") }
        }
        p.waitUntilExit(); pipe.fileHandleForReading.readabilityHandler = nil; activeProcess = nil
        if p.terminationStatus != 0, !allowFailure { throw message("Command failed (\(p.terminationStatus))") }
        lock.lock(); defer { lock.unlock() }; return (p.terminationStatus, lines)
    }

    func capture(_ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    func requireTool(_ path: String, _ name: String) throws -> String {
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            throw message("\(name) not found. Expand Tool Paths and set its location.")
        }
        return path
    }

    func findTool(_ name: String) -> String {
        ["/opt/homebrew/bin","/usr/local/bin","/usr/bin","/bin"]
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    func parseIdx(_ line: String) -> (index: Int, total: Int)? {
        let p = line.split(separator: " ", maxSplits: 1)
        guard let f = p.first else { return nil }
        let ip = f.split(separator: "/")
        guard ip.count == 2, let i = Int(ip[0]), let t = Int(ip[1]) else { return nil }
        return (i, t)
    }

    func timestamp() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    func log(_ value: String) {
        DispatchQueue.main.async {
            // Color-code lines
            let color: NSColor
            if value.contains("❌") || value.contains("Error") || value.contains("error") {
                color = .wsRed
            } else if value.contains("✅") || value.contains("Done") {
                color = .wsGreen
            } else if value.contains("⚠️") || value.contains("Warning") {
                color = .wsYellow
            } else if value.hasPrefix("[") {
                color = NSColor(red: 0.40, green: 0.75, blue: 0.95, alpha: 1) // timestamp = cyan
            } else {
                color = NSColor(red: 0.70, green: 0.70, blue: 0.80, alpha: 1)
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .foregroundColor: color
            ]
            self.logView.textStorage?.append(NSAttributedString(string: value + "\n", attributes: attrs))
            self.logView.scrollToEndOfDocument(nil)
        }
    }

    func alert(_ value: String) {
        DispatchQueue.main.async {
            let a = NSAlert(); a.messageText = "MediaDownloader"; a.informativeText = value; a.runModal()
        }
    }

    func message(_ value: String) -> NSError {
        NSError(domain: "MediaDownloader", code: 1, userInfo: [NSLocalizedDescriptionKey: value])
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = MediaDownloaderDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

extension MediaDownloaderDelegate: NSComboBoxDelegate, NSControlTextEditingDelegate {
    func controlTextDidChange(_ obj: Notification) {
        autoSelectModeIfHelpful(for: urlCombo.stringValue)
        updateSourceGuidance()
    }
}
