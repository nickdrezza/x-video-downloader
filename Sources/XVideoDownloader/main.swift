import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let inputTextView = NSTextView()
    private let pasteButton = NSButton(title: "Paste", target: nil, action: nil)
    private let folderLabel = NSTextField(labelWithString: "No folder selected")
    private let chooseFolderButton = NSButton(title: "Choose Folder…", target: nil, action: nil)
    private let downloadButton = NSButton(title: "Download Videos", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "Paste one or more X/Twitter post URLs to begin.")
    private let logTextView = NSTextView()

    private var selectedFolder: URL?
    private var activeProcess: Process?
    private var outputPipe: Pipe?
    private var pendingOutput = Data()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        buildInterface()
        restoreFolder()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(inputTextView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildInterface() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "X Video Downloader"
        window.isRestorable = false
        window.center()
        window.backgroundColor = .windowBackgroundColor

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView?.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20)
        ])

        let title = NSTextField(labelWithString: "Download videos from X")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        root.addArrangedSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString: "Paste X or Twitter post links. One per line—or mixed into any text.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(subtitle)
        subtitle.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let inputHeader = NSStackView()
        inputHeader.orientation = .horizontal
        inputHeader.alignment = .centerY
        let inputLabel = NSTextField(labelWithString: "Post links")
        inputLabel.font = .systemFont(ofSize: 12, weight: .medium)
        inputHeader.addArrangedSubview(inputLabel)
        let inputSpacer = NSView()
        inputSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inputHeader.addArrangedSubview(inputSpacer)
        pasteButton.bezelStyle = .accessoryBarAction
        pasteButton.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste")
        pasteButton.imagePosition = .imageLeading
        pasteButton.target = self
        pasteButton.action = #selector(pasteLinks)
        inputHeader.addArrangedSubview(pasteButton)
        root.addArrangedSubview(inputHeader)
        inputHeader.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        inputTextView.font = .systemFont(ofSize: 13)
        inputTextView.isRichText = false
        inputTextView.isAutomaticLinkDetectionEnabled = true
        inputTextView.string = ""
        let inputScroll = NSScrollView()
        inputScroll.hasVerticalScroller = true
        inputScroll.borderType = .lineBorder
        inputScroll.documentView = inputTextView
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(inputScroll)
        inputScroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        inputScroll.heightAnchor.constraint(equalToConstant: 112).isActive = true

        let folderRow = NSStackView()
        folderRow.orientation = .horizontal
        folderRow.alignment = .centerY
        folderRow.spacing = 8
        let folderIcon = NSImageView(image: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Download folder")!)
        folderIcon.contentTintColor = .secondaryLabelColor
        folderRow.addArrangedSubview(folderIcon)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFolder)
        chooseFolderButton.bezelStyle = .rounded
        folderRow.addArrangedSubview(folderLabel)
        folderRow.addArrangedSubview(chooseFolderButton)
        root.addArrangedSubview(folderRow)
        folderRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10
        downloadButton.bezelStyle = .rounded
        downloadButton.controlSize = .large
        downloadButton.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Download")
        downloadButton.imagePosition = .imageLeading
        downloadButton.keyEquivalent = "\r"
        downloadButton.target = self
        downloadButton.action = #selector(startDownload)
        cancelButton.target = self
        cancelButton.action = #selector(cancelDownload)
        cancelButton.isEnabled = false
        cancelButton.bezelStyle = .rounded
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        actionRow.addArrangedSubview(downloadButton)
        actionRow.addArrangedSubview(cancelButton)
        actionRow.addArrangedSubview(progressIndicator)
        root.addArrangedSubview(actionRow)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        root.addArrangedSubview(statusLabel)
        statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let logLabel = NSTextField(labelWithString: "Activity")
        logLabel.font = .systemFont(ofSize: 12, weight: .medium)
        root.addArrangedSubview(logLabel)

        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.isEditable = false
        logTextView.isRichText = false
        logTextView.backgroundColor = NSColor.textBackgroundColor
        let logScroll = NSScrollView()
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .lineBorder
        logScroll.documentView = logTextView
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(logScroll)
        logScroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        logScroll.heightAnchor.constraint(equalToConstant: 105).isActive = true
    }

    private func buildMenus() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About X Video Downloader", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit X Video Downloader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func pasteLinks() {
        window.makeFirstResponder(inputTextView)
        inputTextView.paste(nil)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where downloaded videos should be saved"
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let selectedFolder {
            panel.directoryURL = selectedFolder
        }

        if panel.runModal() == .OK, let folder = panel.url {
            selectedFolder = folder
            folderLabel.stringValue = folder.path
            UserDefaults.standard.set(folder.path, forKey: "downloadFolder")
            statusLabel.stringValue = "Ready."
        }
    }

    private func restoreFolder() {
        let defaultPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let path = UserDefaults.standard.string(forKey: "downloadFolder") ?? defaultPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            selectedFolder = URL(fileURLWithPath: path, isDirectory: true)
            folderLabel.stringValue = path
            UserDefaults.standard.set(path, forKey: "downloadFolder")
        }
    }

    @objc private func startDownload() {
        guard activeProcess == nil else { return }

        let urls = extractPostURLs(from: inputTextView.string)
        guard !urls.isEmpty else {
            showAlert(title: "No post links found", message: "Paste at least one x.com or twitter.com URL containing /status/ followed by the post ID.")
            return
        }
        guard let folder = selectedFolder else {
            showAlert(title: "Choose a folder", message: "Select where the downloaded videos should be saved.")
            return
        }
        guard let ytDlp = findExecutable(named: "yt-dlp") else {
            showMissingDependencyAlert()
            return
        }
        guard findExecutable(named: "ffmpeg") != nil else {
            showMissingDependencyAlert()
            return
        }

        logTextView.string = ""
        appendLog("Found \(urls.count) unique post link\(urls.count == 1 ? "" : "s").\n")
        appendLog("Saving to: \(folder.path)\n\n")

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ytDlp)
        process.currentDirectoryURL = folder
        process.standardOutput = pipe
        process.standardError = pipe

        var environment = ProcessInfo.processInfo.environment
        let usefulPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let inheritedPath = environment["PATH"].map { [$0] } ?? []
        environment["PATH"] = (usefulPaths + inheritedPath).joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        let outputTemplate = folder.appendingPathComponent("%(uploader_id|unknown)s_%(id)s_%(playlist_index|single)s.%(ext)s").path
        process.arguments = [
            "--newline",
            "--ignore-config",
            "--no-progress",
            "--format", "bv*+ba/b",
            "--merge-output-format", "mp4",
            "--no-overwrites",
            "--restrict-filenames",
            "--output", outputTemplate,
            "--"
        ] + urls

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async {
                self?.consumeOutput(data)
            }
        }

        process.terminationHandler = { [weak self] completed in
            DispatchQueue.main.async {
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                if !self.pendingOutput.isEmpty {
                    self.flushPendingOutput()
                }
                let wasCancelled = completed.terminationReason == .uncaughtSignal
                self.finishDownload(exitCode: completed.terminationStatus, wasCancelled: wasCancelled)
            }
        }

        do {
            activeProcess = process
            outputPipe = pipe
            setRunning(true)
            statusLabel.stringValue = "Downloading \(urls.count) post\(urls.count == 1 ? "" : "s")…"
            try process.run()
        } catch {
            activeProcess = nil
            outputPipe = nil
            setRunning(false)
            showAlert(title: "Could not start the downloader", message: error.localizedDescription)
        }
    }

    @objc private func cancelDownload() {
        guard let process = activeProcess, process.isRunning else { return }
        appendLog("\nCancelling…\n")
        process.terminate()
        cancelButton.isEnabled = false
    }

    private func finishDownload(exitCode: Int32, wasCancelled: Bool) {
        activeProcess = nil
        outputPipe = nil
        setRunning(false)

        if wasCancelled {
            statusLabel.stringValue = "Cancelled. Any completed files remain in the selected folder."
            appendLog("\nCancelled.\n")
        } else if exitCode == 0 {
            statusLabel.stringValue = "Finished successfully."
            appendLog("\nFinished successfully.\n")
            NSSound.beep()
        } else {
            statusLabel.stringValue = "Finished with one or more errors. See Activity for details."
            appendLog("\nDownloader exited with code \(exitCode).\n")
        }
    }

    private func setRunning(_ running: Bool) {
        inputTextView.isEditable = !running
        pasteButton.isEnabled = !running
        chooseFolderButton.isEnabled = !running
        downloadButton.isEnabled = !running
        cancelButton.isEnabled = running
        if running {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    private func consumeOutput(_ data: Data) {
        pendingOutput.append(data)
        flushPendingOutput()
    }

    private func flushPendingOutput() {
        guard let text = String(data: pendingOutput, encoding: .utf8) else { return }
        pendingOutput.removeAll(keepingCapacity: true)
        appendLog(text)
    }

    private func appendLog(_ text: String) {
        logTextView.textStorage?.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]))
        logTextView.scrollToEndOfDocument(nil)
    }

    private func extractPostURLs(from text: String) -> [String] {
        let pattern = #"(?:https?://)?(?:(?:www|mobile)\.)?(?:x\.com|twitter\.com)/[A-Za-z0-9_]+/status/([0-9]+)(?:[^\s<>“”]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var seenIDs = Set<String>()
        var results: [String] = []

        for match in regex.matches(in: text, range: fullRange) {
            guard match.numberOfRanges > 1,
                  let idRange = Range(match.range(at: 1), in: text) else { continue }
            let postID = String(text[idRange])
            guard seenIDs.insert(postID).inserted else { continue }
            results.append("https://x.com/i/status/\(postID)")
        }
        return results
    }

    private func findExecutable(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func showMissingDependencyAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Downloader components are missing"
        alert.informativeText = "Install yt-dlp and ffmpeg once with Homebrew, then reopen this app:\n\nbrew install yt-dlp ffmpeg"
        alert.addButton(withTitle: "Copy Install Command")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew install yt-dlp ffmpeg", forType: .string)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.regular)
application.run()
