import AppKit
import Foundation

private enum OperationMode: String {
    case downloadAndCompress = "download"
    case compressOnly = "compress"
}

private struct BrowserCookieOption {
    let title: String
    let identifier: String
}

private final class MediaDropTextView: NSTextView {
    var onFileURLsDropped: (([URL]) -> Void)?
    var onReadOnlyClick: (() -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onFileURLsDropped?(urls)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if !isEditable, let onReadOnlyClick {
            onReadOnlyClick()
            return
        }
        super.mouseDown(with: event)
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) ?? []
        return objects.compactMap { object in
            guard let url = object as? NSURL else { return nil }
            return url.isFileURL ? url as URL : nil
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let browserOptions = [
        BrowserCookieOption(title: "Safari", identifier: "safari"),
        BrowserCookieOption(title: "Chrome", identifier: "chrome"),
        BrowserCookieOption(title: "Firefox", identifier: "firefox"),
        BrowserCookieOption(title: "Edge", identifier: "edge"),
        BrowserCookieOption(title: "Brave", identifier: "brave"),
        BrowserCookieOption(title: "Chromium", identifier: "chromium"),
        BrowserCookieOption(title: "Opera", identifier: "opera"),
        BrowserCookieOption(title: "Vivaldi", identifier: "vivaldi")
    ]

    private var window: NSWindow!
    private let modeControl = NSSegmentedControl(labels: ["Download & Compress", "Compress Only"], trackingMode: .selectOne, target: nil, action: nil)
    private let inputTextView = MediaDropTextView()
    private let folderLabel = NSTextField(labelWithString: "No folder selected")
    private let chooseFolderButton = NSButton(title: "Choose Folder…", target: nil, action: nil)
    private let maxSizeField = NSTextField()
    private let unitControl = NSSegmentedControl(labels: ["KB", "MB"], trackingMode: .selectOne, target: nil, action: nil)
    private let actionButton = NSButton(title: "Download", target: nil, action: nil)
    private let logsButton = NSButton(title: "Logs", target: nil, action: nil)
    private let activityScroll = NSScrollView()
    private let activityTextView = NSTextView()
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "Paste X image/video links to download.")

    private let compactContentHeight: CGFloat = 360
    private let logsContentHeight: CGFloat = 500

    private var selectedFolder: URL?
    private var selectedFiles: [URL] = []
    private var operationMode: OperationMode = .downloadAndCompress
    private var activityExpanded = false
    private var workRunning = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        buildInterface()
        restoreFolder()
        restoreCookieBrowser()
        configureInputForMode()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(inputTextView)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.showPermissionsSetupIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.showPermissionsSetupIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func buildInterface() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: compactContentHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "X Downloader"
        window.isRestorable = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        let contentView = NSView(frame: NSRect(
            origin: .zero,
            size: window.contentRect(forFrameRect: window.frame).size
        ))
        window.contentView = contentView
        contentView.addSubview(root)
        root.frame = contentView.bounds.insetBy(dx: 24, dy: 24)
        root.autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: "X Downloader")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        root.addArrangedSubview(title)

        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.controlSize = .large
        modeControl.selectedSegment = 0
        root.addArrangedSubview(modeControl)
        modeControl.widthAnchor.constraint(equalToConstant: 300).isActive = true

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(subtitleLabel)
        subtitleLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        inputTextView.font = .systemFont(ofSize: 13)
        inputTextView.isRichText = false
        inputTextView.isAutomaticLinkDetectionEnabled = true
        inputTextView.textContainerInset = NSSize(width: 10, height: 10)
        inputTextView.onFileURLsDropped = { [weak self] urls in
            self?.selectFiles(urls)
        }
        inputTextView.onReadOnlyClick = { [weak self] in
            self?.chooseFiles()
        }

        let inputScroll = NSScrollView()
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.borderType = .bezelBorder
        inputScroll.drawsBackground = true
        inputScroll.backgroundColor = .textBackgroundColor
        inputScroll.documentView = inputTextView
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(inputScroll)
        inputScroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        inputScroll.heightAnchor.constraint(equalToConstant: 132).isActive = true

        let outputRow = NSStackView()
        outputRow.orientation = .horizontal
        outputRow.alignment = .centerY
        outputRow.spacing = 8
        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFolder)
        chooseFolderButton.bezelStyle = .rounded
        outputRow.addArrangedSubview(chooseFolderButton)
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        outputRow.addArrangedSubview(folderLabel)
        let outputSpacer = NSView()
        outputSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        outputRow.addArrangedSubview(outputSpacer)
        let maxLabel = NSTextField(labelWithString: "Max size:")
        maxLabel.textColor = .secondaryLabelColor
        outputRow.addArrangedSubview(maxLabel)
        maxSizeField.stringValue = "20"
        maxSizeField.placeholderString = "No limit"
        maxSizeField.alignment = .right
        maxSizeField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        maxSizeField.widthAnchor.constraint(equalToConstant: 76).isActive = true
        outputRow.addArrangedSubview(maxSizeField)
        unitControl.controlSize = .regular
        unitControl.selectedSegment = 1
        outputRow.addArrangedSubview(unitControl)
        unitControl.widthAnchor.constraint(equalToConstant: 112).isActive = true
        root.addArrangedSubview(outputRow)
        outputRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8
        actionButton.target = self
        actionButton.action = #selector(startOperation)
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .large
        actionButton.keyEquivalent = "\r"
        actionRow.addArrangedSubview(actionButton)
        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionRow.addArrangedSubview(actionSpacer)
        logsButton.setButtonType(.toggle)
        logsButton.bezelStyle = .rounded
        logsButton.controlSize = .large
        logsButton.target = self
        logsButton.action = #selector(toggleLogs)
        actionRow.addArrangedSubview(logsButton)
        root.addArrangedSubview(actionRow)

        activityTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        activityTextView.isEditable = false
        activityTextView.isRichText = false
        activityTextView.textContainerInset = NSSize(width: 8, height: 8)
        activityScroll.hasVerticalScroller = true
        activityScroll.autohidesScrollers = true
        activityScroll.borderType = .bezelBorder
        activityScroll.documentView = activityTextView
        activityScroll.translatesAutoresizingMaskIntoConstraints = false
        activityScroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        activityScroll.heightAnchor.constraint(equalToConstant: 122).isActive = true
        activityScroll.isHidden = true
        root.addArrangedSubview(activityScroll)
    }

    private func buildMenus() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About X Downloader", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())

        let cookiesItem = NSMenuItem(title: "Browser Cookies", action: nil, keyEquivalent: "")
        let cookiesMenu = NSMenu(title: "Browser Cookies")
        for option in browserOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectCookieBrowser(_:)), keyEquivalent: "")
            item.representedObject = option.identifier
            cookiesMenu.addItem(item)
        }
        cookiesItem.submenu = cookiesMenu
        appMenu.addItem(cookiesItem)
        appMenu.addItem(withTitle: "Permissions Setup…", action: #selector(showPermissionsSetup), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit X Downloader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    @objc private func modeChanged() {
        operationMode = modeControl.selectedSegment == 1
            ? .compressOnly
            : .downloadAndCompress
        configureInputForMode()
    }

    private func configureInputForMode() {
        let isCompressOnly = operationMode == .compressOnly
        subtitleLabel.stringValue = isCompressOnly
            ? "Select images/videos to compress."
            : "Paste X image/video links to download."
        actionButton.title = isCompressOnly ? "Compress" : "Download"
        inputTextView.isEditable = !isCompressOnly && !workRunning
        inputTextView.isSelectable = !isCompressOnly
        inputTextView.toolTip = isCompressOnly
            ? "Drop files here or click to select multiple files."
            : "Paste supported X, Reddit, or RedGifs links here."
        if isCompressOnly { updateSelectedFileText() }
    }

    @objc private func selectCookieBrowser(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        UserDefaults.standard.set(identifier, forKey: "cookieBrowser")
        updateCookieMenuStates()
        appendActivity("Using \(cookieBrowserDisplayName) browser cookies.\n")
    }

    private func restoreCookieBrowser() {
        if UserDefaults.standard.string(forKey: "cookieBrowser") == nil {
            UserDefaults.standard.set("safari", forKey: "cookieBrowser")
        }
        updateCookieMenuStates()
    }

    private func showPermissionsSetupIfNeeded() {
        let key = "didShowPermissionsSetup"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        showPermissionsSetup()
    }

    @objc private func showPermissionsSetup() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Set up browser-cookie access"
        alert.informativeText = "X Downloader uses your selected browser's cookies to access media your account is allowed to view. Grant Full Disk Access to X Downloader in macOS Privacy & Security, then relaunch the app."
        alert.addButton(withTitle: "Open Full Disk Access")
        alert.addButton(withTitle: "Later")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.openFullDiskAccessSettings()
        }
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateCookieMenuStates() {
        guard let cookiesMenu = NSApp.mainMenu?.item(at: 0)?.submenu?.item(withTitle: "Browser Cookies")?.submenu else { return }
        let selected = cookieBrowserIdentifier
        for item in cookiesMenu.items {
            item.state = (item.representedObject as? String) == selected ? .on : .off
        }
    }

    private var cookieBrowserIdentifier: String {
        UserDefaults.standard.string(forKey: "cookieBrowser") ?? "safari"
    }

    private var cookieBrowserDisplayName: String {
        browserOptions.first(where: { $0.identifier == cookieBrowserIdentifier })?.title ?? "Safari"
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose output folder"
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedFolder

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        selectedFolder = folder
        folderLabel.stringValue = shortenedPath(folder.path)
        UserDefaults.standard.set(folder.path, forKey: "downloadFolder")
    }

    private func restoreFolder() {
        let defaultPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let path = UserDefaults.standard.string(forKey: "downloadFolder") ?? defaultPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            selectedFolder = URL(fileURLWithPath: path, isDirectory: true)
            folderLabel.stringValue = shortenedPath(path)
        }
    }

    private func shortenedPath(_ path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents
        if components.count <= 2 { return path }
        return "…/\(components.last ?? path)"
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose media files"
        panel.prompt = "Choose Files"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        selectFiles(panel.urls)
    }

    private func selectFiles(_ urls: [URL]) {
        let files = urls.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        guard !files.isEmpty else { return }
        var seen = Set(selectedFiles.map { $0.standardizedFileURL.path })
        for file in files where seen.insert(file.standardizedFileURL.path).inserted {
            selectedFiles.append(file)
        }
        updateSelectedFileText()
    }

    private func updateSelectedFileText() {
        inputTextView.string = selectedFiles.map { $0.lastPathComponent }.joined(separator: "\n")
    }

    @objc private func startOperation() {
        guard !workRunning else { return }
        guard let outputFolder = selectedFolder else {
            showAlert(title: "Choose a folder", message: "Select where the output files should be saved.")
            return
        }

        let targetBytes: Int64?
        do {
            targetBytes = try parseTargetBytes()
        } catch {
            showAlert(title: "Invalid max size", message: error.localizedDescription)
            return
        }

        let urls: [String]
        let files: [URL]
        if operationMode == .downloadAndCompress {
            urls = extractSupportedURLs(from: inputTextView.string)
            files = []
            guard !urls.isEmpty else {
                showAlert(title: "No supported links found", message: "Paste X, Reddit, or RedGifs links containing media.")
                return
            }
        } else {
            urls = []
            files = selectedFiles
            guard !files.isEmpty else {
                showAlert(title: "Choose media files", message: "Drop files into the box or click it to select one or more files.")
                return
            }
        }

        guard let ffmpeg = findExecutable(named: "ffmpeg"), let ffprobe = findExecutable(named: "ffprobe") else {
            showMissingDependencyAlert(missing: "ffmpeg and ffprobe")
            return
        }
        if operationMode == .downloadAndCompress {
            guard findExecutable(named: "yt-dlp") != nil, findExecutable(named: "gallery-dl") != nil else {
                showMissingDependencyAlert(missing: "yt-dlp and gallery-dl")
                return
            }
        }

        activityTextView.string = ""
        activityExpanded = false
        logsButton.state = .off
        activityScroll.isHidden = true
        resizeWindow(toContentHeight: compactContentHeight)
        workRunning = true
        setControlsRunning(true)
        appendActivity("Mode: \(operationMode == .downloadAndCompress ? "Download + compress" : "Compress only")\n")
        appendActivity("Output: \(outputFolder.path)\n")
        appendActivity("Max size: \(targetBytes.map(formatTarget) ?? "no limit")\n\n")

        let browser = cookieBrowserIdentifier
        let mode = operationMode
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.performOperation(
                    mode: mode,
                    urls: urls,
                    files: files,
                    outputFolder: outputFolder,
                    targetBytes: targetBytes,
                    cookieBrowser: browser,
                    ffmpeg: ffmpeg,
                    ffprobe: ffprobe
                )
                self.finishOperation(message: "Finished successfully.")
            } catch {
                self.finishOperation(message: error.localizedDescription, failed: true)
            }
        }
    }

    private func performOperation(
        mode: OperationMode,
        urls: [String],
        files: [URL],
        outputFolder: URL,
        targetBytes: Int64?,
        cookieBrowser: String,
        ffmpeg: String,
        ffprobe: String
    ) throws {
        let engine = MediaCompressionEngine(ffmpegPath: ffmpeg, ffprobePath: ffprobe)
        var sourceFiles = files
        var temporaryDirectory: URL?
        defer {
            if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
        }

        if mode == .downloadAndCompress {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("XDownloader-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            temporaryDirectory = temp
            sourceFiles = try downloadMedia(urls: urls, into: temp, cookieBrowser: cookieBrowser)
        }

        guard !sourceFiles.isEmpty else {
            throw NSError(domain: "XDownloader", code: 1, userInfo: [NSLocalizedDescriptionKey: "No supported media files were found."])
        }

        appendActivity("Found \(sourceFiles.count) media file\(sourceFiles.count == 1 ? "" : "s").\n")
        for (index, source) in sourceFiles.enumerated() {
            let kind = engine.kind(for: source)
            guard kind != .unsupported else {
                appendActivity("Skipped unsupported file: \(source.lastPathComponent)\n")
                continue
            }

            appendActivity("[\(index + 1)/\(sourceFiles.count)] \(targetBytes == nil ? "Copying" : "Compressing") \(source.lastPathComponent)…\n")
            let destination: URL
            let outputBytes: Int64
            if let targetBytes {
                let effectiveTarget = min(targetBytes, try fileSize(source))
                let extensionName = kind == .image ? "jpg" : "mp4"
                destination = uniqueOutputURL(folder: outputFolder, source: source, suffix: "_c", extensionName: extensionName)
                outputBytes = try engine.compress(inputURL: source, outputURL: destination, targetBytes: effectiveTarget, run: runCommand)
            } else {
                destination = uniqueOutputURL(folder: outputFolder, source: source, suffix: "", extensionName: source.pathExtension)
                try FileManager.default.copyItem(at: source, to: destination)
                outputBytes = try fileSize(destination)
            }
            appendActivity("Saved \(destination.lastPathComponent) (\(formatSize(outputBytes))).\n")
        }
    }

    private func downloadMedia(urls: [String], into directory: URL, cookieBrowser: String) throws -> [URL] {
        guard let galleryDL = findExecutable(named: "gallery-dl"), let ytDlp = findExecutable(named: "yt-dlp") else {
            throw NSError(domain: "XDownloader", code: 2, userInfo: [NSLocalizedDescriptionKey: "yt-dlp and gallery-dl are required for downloads."])
        }

        appendActivity("Using \(cookieBrowserDisplayName(for: cookieBrowser)) browser cookies.\n")
        appendActivity("Downloading images…\n")
        let imageFilter = "extension in ('jpg', 'jpeg', 'jfif', 'png', 'apng', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'avif', 'heic', 'heif')"
        let galleryArguments = [
            "--config-ignore", "--no-colors", "--no-mtime", "--no-part",
            "--restrict-filenames", "ascii+", "--directory", directory.path,
            "--cookies-from-browser", cookieBrowser,
            "--filter", imageFilter
        ] + urls
        let result = try runCommand(galleryDL, galleryArguments)
        if result.status != 0 { appendActivity("gallery-dl completed with errors; continuing.\n") }

        appendActivity("Downloading videos…\n")
        let outputTemplate = directory.appendingPathComponent("media_%(extractor)s_%(id)s_%(autonumber)s.%(ext)s").path
        let ytArguments = [
            "--newline", "--ignore-config", "--no-progress", "--ignore-errors", "--no-abort-on-error",
            "--cookies-from-browser", cookieBrowser,
            "--format", "bv*+ba/b", "--merge-output-format", "mp4", "--no-overwrites", "--restrict-filenames",
            "--output", outputTemplate, "--"
        ] + urls
        let ytResult = try runCommand(ytDlp, ytArguments)
        if ytResult.status != 0 { appendActivity("yt-dlp completed with skipped links or errors.\n") }

        return mediaFiles(in: directory)
    }

    private func runCommand(_ executable: String, _ arguments: [String]) throws -> MediaCommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        var environment = ProcessInfo.processInfo.environment
        let usefulPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let inheritedPath = environment["PATH"].map { [$0] } ?? []
        environment["PATH"] = (usefulPaths + inheritedPath).joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        let outputLock = NSLock()
        var output = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputLock.lock()
            output.append(data)
            outputLock.unlock()
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
        outputLock.lock()
        output.append(remainder)
        let outputText = String(data: output, encoding: .utf8) ?? String(decoding: output, as: UTF8.self)
        outputLock.unlock()

        if !outputText.isEmpty {
            appendActivity(outputText.hasSuffix("\n") ? outputText : outputText + "\n")
        }
        return MediaCommandResult(status: process.terminationStatus, output: outputText)
    }

    private func mediaFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let engine = MediaCompressionEngine(ffmpegPath: "", ffprobePath: "")
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  !url.pathExtension.lowercased().hasSuffix("part"),
                  engine.kind(for: url) != .unsupported else { return nil }
            return url
        }.sorted { $0.path < $1.path }
    }

    private func uniqueOutputURL(folder: URL, source: URL, suffix: String, extensionName: String) -> URL {
        let rawBase = source.deletingPathExtension().lastPathComponent
        let base = rawBase.isEmpty ? "media" : rawBase
        let cleanedBase = base.replacingOccurrences(of: "/", with: "_")
        let normalizedExtension = extensionName.isEmpty ? "" : ".\(extensionName.lowercased())"
        var candidate = folder.appendingPathComponent("\(cleanedBase)\(suffix)\(normalizedExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(cleanedBase)\(suffix)_\(counter)\(normalizedExtension)")
            counter += 1
        }
        return candidate
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let number = attributes[.size] as? NSNumber else {
            throw NSError(domain: "XDownloader", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not read the file size for \(url.lastPathComponent)."])
        }
        return number.int64Value
    }

    private func parseTargetBytes() throws -> Int64? {
        let text = maxSizeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard let value = Double(text), value.isFinite, value > 0 else { throw MediaCompressionError.invalidTarget }
        let multiplier: Double = unitControl.selectedSegment == 0 ? 1024 : 1024 * 1024
        let bytes = value * multiplier
        guard bytes.isFinite, bytes >= 1, bytes <= Double(Int64.max) else { throw MediaCompressionError.invalidTarget }
        return Int64(bytes.rounded())
    }

    private func formatTarget(_ bytes: Int64) -> String {
        let unit = unitControl.selectedSegment == 0 ? "KB" : "MB"
        let divisor: Double = unit == "KB" ? 1024 : 1024 * 1024
        return String(format: "%.2f %@", Double(bytes) / divisor, unit)
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 * 1024 { return String(format: "%.2f KB", Double(bytes) / 1024) }
        return String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
    }

    private func finishOperation(message: String, failed: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appendActivity("\n\(message)\n")
            self.workRunning = false
            self.setControlsRunning(false)
            if failed { NSSound.beep() }
        }
    }

    private func setControlsRunning(_ running: Bool) {
        modeControl.isEnabled = !running
        chooseFolderButton.isEnabled = !running
        maxSizeField.isEnabled = !running
        unitControl.isEnabled = !running
        actionButton.isEnabled = !running
        inputTextView.isEditable = !running && operationMode == .downloadAndCompress
    }

    @objc private func toggleLogs() {
        activityExpanded.toggle()
        activityScroll.isHidden = !activityExpanded
        logsButton.state = activityExpanded ? .on : .off
        resizeWindow(toContentHeight: activityExpanded ? logsContentHeight : compactContentHeight)
        if activityExpanded {
            window.layoutIfNeeded()
            activityTextView.scrollToEndOfDocument(nil)
        }
    }

    private func resizeWindow(toContentHeight height: CGFloat) {
        var frame = window.frame
        let currentContentHeight = window.contentRect(forFrameRect: frame).height
        guard abs(currentContentHeight - height) > 0.5 else { return }
        let contentRect = NSRect(x: 0, y: 0, width: frame.width, height: height)
        let targetFrame = window.frameRect(forContentRect: contentRect)
        frame.origin.y += frame.height - targetFrame.height
        frame.size = targetFrame.size
        window.setFrame(frame, display: true, animate: true)
    }

    private func appendActivity(_ text: String) {
        let append = { [weak self] in
            guard let self else { return }
            self.activityTextView.textStorage?.append(NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]))
            self.activityTextView.scrollToEndOfDocument(nil)
        }
        if Thread.isMainThread {
            append()
        } else {
            DispatchQueue.main.async(execute: append)
        }
    }

    private func showMissingDependencyAlert(missing: String) {
        showAlert(title: "Missing dependency", message: "Install \(missing) with Homebrew, then try again.")
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func cookieBrowserDisplayName(for identifier: String) -> String {
        browserOptions.first(where: { $0.identifier == identifier })?.title ?? identifier
    }

    private func extractSupportedURLs(from text: String) -> [String] {
        let pattern = #"(?i)(?:https?://)?(?:(?:www|mobile)\.)?(?:x\.com|twitter\.com)/[^\s<>“”]+|(?:https?://)?(?:(?:www|old|new|m)\.)?reddit\.com/[^\s<>“”]+|(?:https?://)?(?:www\.|v3\.)?redgifs\.com/(?:watch|ifr)/[^\s<>“”]+|https?://[^\s<>“”]+\.(?:jpg|jpeg|png|gif|webp|avif)(?:\?[^\s<>“”]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var results: [String] = []
        for match in regex.matches(in: text, range: fullRange) {
            guard let range = Range(match.range, in: text) else { continue }
            let candidate = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\"'"))
            guard let normalized = normalizeSupportedURL(candidate), seen.insert(normalized).inserted else { continue }
            results.append(normalized)
        }
        return results
    }

    private func normalizeSupportedURL(_ candidate: String) -> String? {
        let urlString = candidate.lowercased().hasPrefix("http") ? candidate : "https://\(candidate)"
        guard let components = URLComponents(string: urlString), let host = components.host?.lowercased(), !components.path.isEmpty else { return nil }

        if ["x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"].contains(host) {
            let pattern = #"^/(?:[^/]+|i)/status/([0-9]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: components.path, range: NSRange(components.path.startIndex..<components.path.endIndex, in: components.path)),
                  let idRange = Range(match.range(at: 1), in: components.path) else { return nil }
            return "https://x.com/i/status/\(components.path[idRange])"
        }

        if ["reddit.com", "www.reddit.com", "old.reddit.com", "new.reddit.com", "m.reddit.com"].contains(host) {
            let pattern = #"^/(?:r/[^/]+/comments/[A-Za-z0-9]+(?:/[^/?#]*)?|comments/[A-Za-z0-9]+|(?:u|user)/[^/]+/s/[A-Za-z0-9]+|s/[A-Za-z0-9]+)(?:/)?$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  regex.firstMatch(in: components.path, range: NSRange(components.path.startIndex..<components.path.endIndex, in: components.path)) != nil else { return nil }
            return "https://www.reddit.com\(components.path)"
        }

        if host == "redd.it" || host == "www.redd.it" {
            let pattern = #"^/[A-Za-z0-9]+/?$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  regex.firstMatch(in: components.path, range: NSRange(components.path.startIndex..<components.path.endIndex, in: components.path)) != nil else { return nil }
            return "https://redd.it\(components.path)"
        }

        if ["redgifs.com", "www.redgifs.com", "v3.redgifs.com"].contains(host) {
            let pattern = #"^/(?:watch|ifr)/[^/?#]+/?$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  regex.firstMatch(in: components.path, range: NSRange(components.path.startIndex..<components.path.endIndex, in: components.path)) != nil else { return nil }
            return "https://\(host)\(components.path)"
        }

        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "avif"])
        let pathExtension = URL(fileURLWithPath: components.path).pathExtension.lowercased()
        if imageExtensions.contains(pathExtension) { return candidate }
        return nil
    }

    private func findExecutable(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
