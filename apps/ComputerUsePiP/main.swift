import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

if CommandLine.arguments.contains("--list-windows") {
    WindowLister.runAndExit()
}
if CommandLine.arguments.contains("--capture-status") {
    print(CGPreflightScreenCaptureAccess() ? "granted" : "missing")
    exit(0)
}

private let commandPath = "/tmp/computer-use-pip.json"
private let cardWidth: CGFloat = 292
private let previewMaxHeight: CGFloat = 420

final class PipWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct PipSession: Codable {
    var id: String?
    var app: String
    var color: String?
    var window: PipWindowTarget?
}

struct PipWindowTarget: Codable {
    var id: Int?
    var title: String?
}

struct PipCommand: Codable {
    var command: String?
    var app: String?
    var visible: Bool?
    var sessions: [PipSession]?
}

final class PipController: NSObject, NSWindowDelegate {
    private let panel: PipWindow
    private let root = NSView()
    private let titleLabel = NSTextField(labelWithString: "Computer Use")
    private let sharingLabel = NSTextField(labelWithString: "Currently Sharing")
    private let appLabel = NSTextField(labelWithString: "Waiting for app")
    private let preview = NSImageView()
    private let placeholder = NSTextField(wrappingLabelWithString: "")
    private let stopButton = NSButton(title: "Stop Sharing", target: nil, action: nil)
    private let prevButton = NSButton(title: "‹", target: nil, action: nil)
    private let nextButton = NSButton(title: "›", target: nil, action: nil)
    private let shareIcon = NSImageView()

    private var targetApp = "Simulator"
    private var sessionApps: [String] = ["Simulator"]
    private var sessionWindows: [PipWindowTarget?] = [nil]
    private var sessionIndex = 0
    private var windows: [SCWindow] = []
    private var index = 0
    private var visible = true
    private var lastCommandToken = ""
    private var capturing = false
    private var lastPreviewSize = NSSize.zero

    override init() {
        panel = PipWindow(
            contentRect: NSRect(x: 0, y: 0, width: cardWidth, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        configureChrome()
        layoutChrome(previewHeight: 320)
        positionDefault()
        loadCommand(force: true)
        panel.orderFrontRegardless()

        Timer.scheduledTimer(withTimeInterval: 0.30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.loadCommand(force: false)
        }
    }

    private func configurePanel() {
        panel.delegate = self
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        panel.isOpaque = true
        panel.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Computer Use"
        panel.setFrameAutosaveName("ComputerUsePiP")
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = false
        panel.contentView = root
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
    }

    private func configureChrome() {
        for label in [titleLabel, sharingLabel, appLabel, placeholder] {
            label.drawsBackground = false
            label.isBezeled = false
            label.isEditable = false
            label.isSelectable = false
        }
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        sharingLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        sharingLabel.textColor = .white
        appLabel.font = .systemFont(ofSize: 11, weight: .medium)
        appLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        placeholder.font = .systemFont(ofSize: 12, weight: .medium)
        placeholder.textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
        placeholder.alignment = .center

        shareIcon.image = NSImage(systemSymbolName: "person.line.dotted.person.fill", accessibilityDescription: "Sharing")
        shareIcon.contentTintColor = NSColor(calibratedRed: 0.35, green: 0.62, blue: 1.0, alpha: 1)
        shareIcon.imageScaling = .scaleProportionallyUpOrDown

        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 12
        preview.layer?.masksToBounds = true
        preview.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor

        stopButton.target = self
        stopButton.action = #selector(stopSharing)
        stopButton.bezelStyle = .rounded
        stopButton.isBordered = false
        stopButton.font = .systemFont(ofSize: 14, weight: .semibold)
        stopButton.contentTintColor = .white
        stopButton.wantsLayer = true
        stopButton.layer?.backgroundColor = NSColor(calibratedRed: 0.89, green: 0.22, blue: 0.22, alpha: 1).cgColor
        stopButton.layer?.cornerRadius = 10

        prevButton.target = self
        prevButton.action = #selector(showPrevious)
        nextButton.target = self
        nextButton.action = #selector(showNext)
        for arrow in [prevButton, nextButton] {
            arrow.isBordered = false
            arrow.font = .systemFont(ofSize: 28, weight: .regular)
            arrow.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        }

        let click = NSClickGestureRecognizer(target: self, action: #selector(revealTarget))
        preview.addGestureRecognizer(click)

        root.subviews = [
            titleLabel, shareIcon, sharingLabel, appLabel,
            preview, placeholder, prevButton, nextButton, stopButton
        ]
    }

    private func layoutChrome(previewHeight: CGFloat) {
        let width = cardWidth
        let height: CGFloat = 12 + 18 + 22 + 18 + 8 + previewHeight + 12 + 40 + 14
        let frame = panel.frame
        panel.setContentSize(NSSize(width: width, height: height))
        panel.setFrameOrigin(NSPoint(x: frame.origin.x, y: frame.origin.y + (frame.height - height)))

        titleLabel.frame = NSRect(x: 16, y: height - 28, width: 140, height: 16)
        shareIcon.frame = NSRect(x: width - 36, y: height - 30, width: 18, height: 18)
        sharingLabel.frame = NSRect(x: 16, y: height - 50, width: width - 48, height: 18)
        appLabel.frame = NSRect(x: 16, y: height - 68, width: width - 32, height: 14)
        preview.frame = NSRect(x: 12, y: 66, width: width - 24, height: previewHeight)
        placeholder.frame = preview.frame.insetBy(dx: 16, dy: 24)
        prevButton.frame = NSRect(x: 8, y: 66 + previewHeight / 2 - 18, width: 28, height: 36)
        nextButton.frame = NSRect(x: width - 36, y: 66 + previewHeight / 2 - 18, width: 28, height: 36)
        stopButton.frame = NSRect(x: 12, y: 14, width: width - 24, height: 40)
    }

    private func positionDefault() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        if panel.setFrameUsingName("ComputerUsePiP") {
            panel.setFrame(panel.constrainFrameRect(panel.frame, to: NSScreen.main), display: false)
            return
        }
        panel.setFrameOrigin(NSPoint(x: screen.maxX - cardWidth - 24, y: screen.maxY - panel.frame.height - 24))
    }

    private func loadCommand(force: Bool) {
        let data = (try? Data(contentsOf: URL(fileURLWithPath: commandPath))) ?? Data()
        let token = String(data: data, encoding: .utf8) ?? ""
        if !force && token == lastCommandToken { return }
        lastCommandToken = token
        let command = (try? JSONDecoder().decode(PipCommand.self, from: data)) ?? PipCommand()
        let previousTarget = targetApp
        if let app = command.app, !app.isEmpty {
            targetApp = app
            index = 0
        }
        if let sessions = command.sessions, !sessions.isEmpty {
            sessionApps = sessions.map(\.app)
            sessionWindows = sessions.map(\.window)
            if let app = command.app, let found = sessionApps.firstIndex(of: app) {
                sessionIndex = found
            }
            targetApp = sessionApps[min(sessionIndex, sessionApps.count - 1)]
        } else {
            sessionApps = [targetApp]
            sessionWindows = [nil]
            sessionIndex = 0
        }
        if targetApp != previousTarget {
            windows = []
            index = 0
            lastPreviewSize = .zero
            preview.image = nil
            placeholder.isHidden = false
            placeholder.stringValue = "Connecting to \(targetApp)…"
            appLabel.stringValue = targetApp
        }
        if command.command == "stop" || command.visible == false || command.command == "hide" {
            hide()
            cursorsTeardown()
            if command.command == "stop" {
                notifyTurnEnded()
            }
            return
        }
        show()
    }

    private func tick() {
        guard visible, !capturing else { return }
        capturing = true
        if targetApp.lowercased().contains("simulator") {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSimulatorFramebuffer()
            }
            return
        }
        if !CGPreflightScreenCaptureAccess() {
            captureSharedSnapshot()
            return
        }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.log("shareable content error: \(error.localizedDescription)")
                }
                let all = content?.windows ?? []
                self.windows = self.matchingWindows(in: all)
                self.log("target=\(self.targetApp) matched=\(self.windows.count) total=\(all.count) capture=\(CGPreflightScreenCaptureAccess())")
                self.captureCurrent()
            }
        }
    }

    private func matchingWindows(in all: [SCWindow]) -> [SCWindow] {
        if sessionIndex < sessionWindows.count,
           let targetID = sessionWindows[sessionIndex]?.id,
           let exact = all.first(where: { Int($0.windowID) == targetID }) {
            return [exact]
        }
        let needle = targetApp.lowercased()
        let matched = all.compactMap { window -> (window: SCWindow, score: Int)? in
            let owner = window.owningApplication?.applicationName.lowercased() ?? ""
            let bundle = window.owningApplication?.bundleIdentifier.lowercased() ?? ""
            let title = (window.title ?? "").lowercased()
            let blob = "\(owner) \(bundle) \(title)"
            let size = window.frame
            guard size.width >= 120, size.height >= 160 else { return nil }
            if owner == needle || bundle == needle {
                return (window, 3)
            }
            if needle.contains("simulator") && (owner.contains("simulator") || bundle.contains("iphonesimulator")) {
                return (window, 2)
            }
            if blob.contains(needle) {
                return (window, 1)
            }
            return nil
        }
        return matched.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.window.frame.width * $0.window.frame.height
                > $1.window.frame.width * $1.window.frame.height
        }.map(\.window)
    }

    private func captureCurrent() {
        if windows.isEmpty {
            preview.image = nil
            placeholder.isHidden = false
            placeholder.stringValue = CGPreflightScreenCaptureAccess()
                ? "Waiting for \(targetApp)…"
                : "Screen Recording is off for this PiP app. Simulator previews still work without it."
            appLabel.stringValue = targetApp
            capturing = false
            return
        }
        if index >= windows.count { index = 0 }
        let window = windows[index]
        let owner = window.owningApplication?.applicationName ?? targetApp
        let title = window.title ?? ""
        appLabel.stringValue = title.isEmpty ? owner : "\(owner) · \(title)"
        placeholder.isHidden = true
        prevButton.isHidden = windows.count < 2 && sessionApps.count < 2
        nextButton.isHidden = windows.count < 2 && sessionApps.count < 2

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale: CGFloat = 2
        config.width = max(200, Int(window.frame.width * scale))
        config.height = max(200, Int(window.frame.height * scale))
        config.showsCursor = false
        config.queueDepth = 1
        if #available(macOS 15.0, *) {
            config.captureResolution = .best
        }

        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { [weak self] image, error in
            DispatchQueue.main.async {
                defer { self?.capturing = false }
                guard let self else { return }
                if let error {
                    self.log("capture error: \(error.localizedDescription)")
                    self.placeholder.isHidden = false
                    self.placeholder.stringValue = CGPreflightScreenCaptureAccess()
                        ? "Could not capture \(self.targetApp)."
                        : "Screen Recording is off for Computer Use PiP. Simulator still works."
                    return
                }
                guard let image else {
                    self.placeholder.isHidden = false
                    self.placeholder.stringValue = "Could not capture \(self.targetApp)."
                    return
                }
                let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                self.preview.image = nsImage
                self.placeholder.isHidden = true
                let ratio = nsImage.size.height / max(nsImage.size.width, 1)
                let previewHeight = min(previewMaxHeight, max(210, (cardWidth - 24) * ratio))
                let size = NSSize(width: nsImage.size.width, height: nsImage.size.height)
                if abs(size.width - self.lastPreviewSize.width) > 12 || abs(size.height - self.lastPreviewSize.height) > 12 {
                    self.lastPreviewSize = size
                    self.layoutChrome(previewHeight: previewHeight)
                }
            }
        }
    }

    private func captureSharedSnapshot() {
        defer { capturing = false }
        let registryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/computer-use/sessions.json")
        guard let data = try? Data(contentsOf: registryURL),
              let registry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessions = registry["sessions"] as? [[String: Any]],
              let session = sessions.last(where: {
                  ($0["status"] as? String) == "active"
                      && (($0["app"] as? String) ?? "").localizedCaseInsensitiveCompare(targetApp) == .orderedSame
              }),
              let path = session["screenshot"] as? String,
              let image = NSImage(contentsOfFile: path) else {
            preview.image = nil
            placeholder.isHidden = false
            placeholder.stringValue = "Waiting for the first \(targetApp) snapshot…"
            appLabel.stringValue = "\(targetApp) · secure snapshot"
            return
        }
        preview.image = image
        placeholder.isHidden = true
        appLabel.stringValue = "\(targetApp) · latest agent snapshot"
        prevButton.isHidden = sessionApps.count < 2
        nextButton.isHidden = sessionApps.count < 2
        let ratio = image.size.height / max(image.size.width, 1)
        let previewHeight = min(previewMaxHeight, max(210, (cardWidth - 24) * ratio))
        let size = image.size
        if abs(size.width - lastPreviewSize.width) > 12 || abs(size.height - lastPreviewSize.height) > 12 {
            lastPreviewSize = size
            layoutChrome(previewHeight: previewHeight)
        }
    }

    private func captureSimulatorFramebuffer() {
        let path = "/tmp/computer-use-pip-sim.png"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["simctl", "io", "booted", "screenshot", "--type=png", path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.capturing = false
                self?.placeholder.isHidden = false
                self?.placeholder.stringValue = "simctl screenshot failed."
                self?.log("simctl error: \(error.localizedDescription)")
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            defer { self?.capturing = false }
            guard let self else { return }
            guard task.terminationStatus == 0, let image = NSImage(contentsOfFile: path) else {
                self.placeholder.isHidden = false
                self.placeholder.stringValue = "Waiting for a booted Simulator…"
                self.appLabel.stringValue = "Simulator"
                return
            }
            self.windows = []
            self.preview.image = image
            self.placeholder.isHidden = true
            self.appLabel.stringValue = sessionApps.count > 1
                ? "\(targetApp) · \(sessionIndex + 1)/\(sessionApps.count)"
                : "Simulator · iOS framebuffer"
            self.prevButton.isHidden = sessionApps.count < 2
            self.nextButton.isHidden = sessionApps.count < 2
            let ratio = image.size.height / max(image.size.width, 1)
            let previewHeight = min(previewMaxHeight, max(210, (cardWidth - 24) * ratio))
            let size = image.size
            if abs(size.width - self.lastPreviewSize.width) > 12 || abs(size.height - self.lastPreviewSize.height) > 12 {
                self.lastPreviewSize = size
                self.layoutChrome(previewHeight: previewHeight)
            }
        }
    }

    private func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/computer-use-pip.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stopSharing()
        return false
    }

    func windowWillMiniaturize(_ notification: Notification) {
        visible = false
        capturing = false
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        visible = true
    }

    private func show() {
        visible = true
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        visible = false
        panel.orderOut(nil)
        capturing = false
    }

    @objc private func stopSharing() {
        hide()
        cursorsTeardown()
        let stopped = Data(#"{"command":"stop","visible":false,"sessions":[]}"#.utf8)
        try? stopped.write(to: URL(fileURLWithPath: commandPath), options: .atomic)
        notifyCleanup()
        NSApp.terminate(nil)
    }

    private func cursorsTeardown() {
        (NSApp.delegate as? AppDelegate)?.cursors?.teardown()
    }

    private func notifyCleanup() {
        let stoppedURL = URL(fileURLWithPath: "/tmp/open-computer-use-stopped")
        try? Data("stopped\n".utf8).write(to: stoppedURL, options: .atomic)
        stopSessionsInRegistry()
        notifyTurnEnded()
        let project = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = project.appendingPathComponent("scripts/cu-cleanup.sh")
        if FileManager.default.isExecutableFile(atPath: script.path) {
            let task = Process()
            task.executableURL = script
            try? task.run()
        }
    }

    private func stopSessionsInRegistry() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/computer-use/sessions.json")
        guard let data = try? Data(contentsOf: url),
              var registry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var sessions = registry["sessions"] as? [[String: Any]] else {
            return
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        for index in sessions.indices where sessions[index]["status"] as? String == "active" {
            sessions[index]["status"] = "stopped"
            sessions[index]["updated_at"] = timestamp
            sessions[index]["cursor"] = ["x": NSNull(), "y": NSNull()]
        }
        registry["sessions"] = sessions
        registry["updated_at"] = timestamp
        guard let encoded = try? JSONSerialization.data(withJSONObject: registry, options: [.prettyPrinted]) else {
            return
        }
        try? encoded.write(to: url, options: .atomic)
    }

    func cancelForSecurityEvent() {
        stopSharing()
    }

    @objc private func showPrevious() {
        if sessionApps.count > 1 {
            sessionIndex = (sessionIndex + sessionApps.count - 1) % sessionApps.count
            targetApp = sessionApps[sessionIndex]
            index = 0
            lastPreviewSize = .zero
            persistSelection()
            return
        }
        guard !windows.isEmpty else { return }
        index = (index + windows.count - 1) % windows.count
    }

    @objc private func showNext() {
        if sessionApps.count > 1 {
            sessionIndex = (sessionIndex + 1) % sessionApps.count
            targetApp = sessionApps[sessionIndex]
            index = 0
            lastPreviewSize = .zero
            persistSelection()
            return
        }
        guard !windows.isEmpty else { return }
        index = (index + 1) % windows.count
    }

    private func persistSelection() {
        let url = URL(fileURLWithPath: commandPath)
        guard let data = try? Data(contentsOf: url),
              var command = try? JSONDecoder().decode(PipCommand.self, from: data) else {
            return
        }
        command.app = targetApp
        command.visible = true
        command.command = "show"
        guard let encoded = try? JSONEncoder().encode(command) else { return }
        try? encoded.write(to: url, options: .atomic)
        lastCommandToken = String(data: encoded, encoding: .utf8) ?? lastCommandToken
    }

    @objc private func revealTarget() {
        let match = NSWorkspace.shared.runningApplications.first {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains(targetApp)
                || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(targetApp)
        }
        match?.activate()
    }

    private func notifyTurnEnded() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", "command -v open-computer-use >/dev/null && open-computer-use turn-ended >/dev/null 2>&1 || true"]
        try? task.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: PipController?
    var cursors: MultiCursorOverlay?
    private var localEscapeMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        controller = PipController()
        cursors = MultiCursorOverlay()
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.controller?.cancelForSecurityEvent()
            return nil
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(sessionBecameInactive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        cursors?.teardown()
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func sessionBecameInactive(_ notification: Notification) {
        controller?.cancelForSecurityEvent()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
