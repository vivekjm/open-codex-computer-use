import AppKit
import Foundation
import ScreenCaptureKit
import Vision

enum WindowLister {
    static func runAndExit() -> Never {
        _ = NSApplication.shared
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, _ in
            var rows: [[String: Any]] = []
            for window in content?.windows ?? [] {
                let frame = window.frame
                guard frame.width >= 100, frame.height >= 80 else { continue }
                let appKitY = primaryHeight - frame.origin.y - frame.height
                rows.append([
                    "id": Int(window.windowID),
                    "app": window.owningApplication?.applicationName ?? "",
                    "bundle": window.owningApplication?.bundleIdentifier ?? "",
                    "title": window.title ?? "",
                    "x": frame.origin.x,
                    "y": frame.origin.y,
                    "width": frame.width,
                    "height": frame.height,
                    "appkit_x": frame.origin.x,
                    "appkit_y": appKitY,
                    "cursor_x": frame.origin.x + 24,
                    "cursor_y": appKitY + frame.height - 48,
                ])
            }
            let envelope: [String: Any] = [
                "primary_height": primaryHeight,
                "windows": rows,
            ]
            let payload = (try? JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted])) ?? Data("[]".utf8)
            FileHandle.standardOutput.write(payload)
            FileHandle.standardOutput.write("\n".data(using: .utf8)!)
            exit(0)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(5))
        FileHandle.standardOutput.write(Data("{\"windows\":[]}\n".utf8))
        exit(1)
    }
}

/// Codex-style software cursor: rounded arrow outline with a soft colored glow.
final class CodexCursorView: NSView {
    var color: NSColor = NSColor(calibratedRed: 0.376, green: 0.416, blue: 0.800, alpha: 1)
    private var currentHotspot = NSPoint(x: 22, y: 36)
    private var targetHotspot = NSPoint(x: 22, y: 36)
    private var motionTimer: Timer?

    override var isFlipped: Bool { false }

    func move(to point: NSPoint, animated: Bool) {
        targetHotspot = point
        if !animated {
            currentHotspot = point
            needsDisplay = true
            return
        }
        guard motionTimer == nil else { return }
        motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let dx = self.targetHotspot.x - self.currentHotspot.x
            let dy = self.targetHotspot.y - self.currentHotspot.y
            if abs(dx) < 0.35, abs(dy) < 0.35 {
                self.currentHotspot = self.targetHotspot
                self.needsDisplay = true
                timer.invalidate()
                self.motionTimer = nil
                return
            }
            // A short ease-out follows actions without the cursor appearing to teleport.
            self.currentHotspot.x += dx * 0.28
            self.currentHotspot.y += dy * 0.28
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let tip = currentHotspot
        let glowRect = NSRect(x: tip.x - 10, y: tip.y - 26, width: 34, height: 34)
        if let glow = NSGradient(colors: [
            color.withAlphaComponent(0.55),
            color.withAlphaComponent(0.12),
            color.withAlphaComponent(0),
        ]) {
            glow.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)
        }

        let arrow = Self.arrow(at: tip)
        color.withAlphaComponent(0.22).setFill()
        arrow.fill()
        NSColor.white.setStroke()
        arrow.lineWidth = 2.1
        arrow.lineJoinStyle = .round
        arrow.lineCapStyle = .round
        arrow.stroke()
        color.setStroke()
        arrow.lineWidth = 1.15
        arrow.stroke()
    }

    static func arrow(at tip: NSPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: NSPoint(x: tip.x + 1.2, y: tip.y - 20))
        path.line(to: NSPoint(x: tip.x + 7.2, y: tip.y - 15.6))
        path.line(to: NSPoint(x: tip.x + 16.8, y: tip.y - 26.4))
        path.line(to: NSPoint(x: tip.x + 20.4, y: tip.y - 23.6))
        path.line(to: NSPoint(x: tip.x + 9.6, y: tip.y - 13.2))
        path.line(to: NSPoint(x: tip.x + 15.6, y: tip.y - 11.6))
        path.close()
        return path
    }
}

final class WindowCursorPanel {
    let panel: NSPanel
    let view = CodexCursorView(frame: .zero)

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view
        view.wantsLayer = true
        view.layer?.masksToBounds = true
    }

    func show(frame: NSRect, hotspot: NSPoint, color: NSColor) {
        let firstPresentation = !panel.isVisible
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.color = color
        view.move(to: hotspot, animated: !firstPresentation)
        if firstPresentation {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

final class MultiCursorOverlay: NSObject {
    private struct OCRHotspot {
        let token: String
        let point: NSPoint
    }

    private var capturing = false
    private var overlays: [String: WindowCursorPanel] = [:]
    private var resolvedHotspots: [String: OCRHotspot] = [:]
    private var resolvingHotspots: Set<String> = []

    override init() {
        super.init()
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func teardown() {
        for overlay in overlays.values {
            overlay.hide()
        }
        overlays.removeAll()
        resolvedHotspots.removeAll()
        resolvingHotspots.removeAll()
        try? Data("[]".utf8).write(to: URL(fileURLWithPath: "/tmp/computer-use-overlay-cursors.json"))
    }

    private func refresh() {
        guard !capturing else { return }
        if commandIsStop() {
            teardown()
            return
        }
        let sessions = activeSessions()
        if sessions.isEmpty {
            teardown()
            return
        }
        render(sessions: sessions, windows: [])
        capturing = true
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, _ in
            DispatchQueue.main.async {
                defer { self?.capturing = false }
                guard let self else { return }
                if self.commandIsStop() || self.activeSessions().isEmpty {
                    self.teardown()
                    return
                }
                self.render(sessions: self.activeSessions(), windows: content?.windows ?? [])
            }
        }
    }

    private func commandIsStop() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/computer-use-pip.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let command = json["command"] as? String ?? ""
        if command == "stop" || command == "hide" { return true }
        if json["visible"] as? Bool == false { return true }
        return false
    }

    private func activeSessions() -> [[String: Any]] {
        let registryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/computer-use/sessions.json")
        guard let data = try? Data(contentsOf: registryURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return (json["sessions"] as? [[String: Any]] ?? []).filter { $0["status"] as? String == "active" }
    }

    private func render(sessions: [[String: Any]], windows: [SCWindow]) {
        var seen: Set<String> = []
        var dump: [[String: Any]] = []
        for session in sessions {
            let id = session["id"] as? String ?? UUID().uuidString
            guard let frame = Self.windowFrame(session: session, windows: windows) else { continue }
            guard frame.width >= 80, frame.height >= 80 else { continue }
            var hotspot = Self.clampedHotspot(session: session, windowFrame: frame)
            if let resolved = resolvedHotspot(session: session, id: id, windowFrame: frame) {
                hotspot = Self.clamp(resolved, windowFrame: frame)
            }
            let color = Self.color(from: session["color"] as? String ?? "#606acc")
            let overlay = overlays[id] ?? WindowCursorPanel()
            overlays[id] = overlay
            overlay.show(frame: frame, hotspot: hotspot, color: color)
            seen.insert(id)
            dump.append([
                "id": id,
                "x": hotspot.x,
                "y": hotspot.y,
                "window_x": frame.origin.x,
                "window_y": frame.origin.y,
                "window_w": frame.width,
                "window_h": frame.height,
            ])
        }
        let staleIDs = overlays.keys.filter { !seen.contains($0) }
        for id in staleIDs {
            overlays[id]?.hide()
            overlays.removeValue(forKey: id)
        }
        let payload = (try? JSONSerialization.data(withJSONObject: dump)) ?? Data("[]".utf8)
        try? payload.write(to: URL(fileURLWithPath: "/tmp/computer-use-overlay-cursors.json"))
    }

    private func resolvedHotspot(
        session: [String: Any],
        id: String,
        windowFrame: NSRect
    ) -> NSPoint? {
        guard let cursor = session["cursor"] as? [String: Any],
              let label = cursor["label"] as? String,
              !label.isEmpty,
              let screenshot = session["screenshot"] as? String,
              FileManager.default.fileExists(atPath: screenshot) else {
            resolvedHotspots.removeValue(forKey: id)
            return nil
        }
        let occurrence = max(1, cursor["occurrence"] as? Int ?? 1)
        let modified = (try? FileManager.default.attributesOfItem(atPath: screenshot)[.modificationDate] as? Date)
            ?? .distantPast
        let token = "\(screenshot)|\(modified.timeIntervalSince1970)|\(label)|\(occurrence)|\(windowFrame.width)x\(windowFrame.height)"
        if let cached = resolvedHotspots[id], cached.token == token {
            return cached.point
        }
        guard !resolvingHotspots.contains(token) else { return nil }
        resolvingHotspots.insert(token)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let point = Self.recognize(
                label: label,
                occurrence: occurrence,
                imagePath: screenshot,
                size: windowFrame.size
            )
            DispatchQueue.main.async {
                guard let self else { return }
                self.resolvingHotspots.remove(token)
                if let point {
                    self.resolvedHotspots[id] = OCRHotspot(token: token, point: point)
                }
            }
        }
        return nil
    }

    private static func recognize(
        label: String,
        occurrence: Int,
        imagePath: String,
        size: NSSize
    ) -> NSPoint? {
        guard let image = NSImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let target = normalizedText(label)
        guard target.count >= 2 else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.005
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            return nil
        }
        var matches: [(score: Int, point: NSPoint)] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let value = normalizedText(candidate.string)
            let score: Int
            if value == target {
                score = 3
            } else if value.contains(target) {
                score = 2
            } else if target.contains(value), value.count >= 3 {
                score = 1
            } else {
                continue
            }
            let box = observation.boundingBox
            let point = NSPoint(x: box.midX * size.width, y: box.midY * size.height)
            matches.append((score, point))
        }
        guard let bestScore = matches.map(\.score).max() else { return nil }
        let ranked = matches
            .filter { $0.score == bestScore }
            .sorted { $0.point.y > $1.point.y }
        return ranked[min(occurrence - 1, ranked.count - 1)].point
    }

    private static func normalizedText(_ text: String) -> String {
        text.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func windowFrame(session: [String: Any], windows: [SCWindow]) -> NSRect? {
        if let live = matchWindow(session: session, windows: windows) {
            return appKitFrame(for: live.frame)
        }
        guard let stored = session["window"] as? [String: Any],
              let x = double(stored["x"]),
              let y = double(stored["y"]),
              let width = double(stored["width"]),
              let height = double(stored["height"]),
              width >= 80, height >= 80 else {
            return nil
        }
        return appKitFrame(for: CGRect(x: x, y: y, width: width, height: height))
    }

    private static func matchWindow(session: [String: Any], windows: [SCWindow]) -> SCWindow? {
        if let stored = session["window"] as? [String: Any],
           let windowID = stored["id"] as? Int,
           let match = windows.first(where: { Int($0.windowID) == windowID }) {
            return match
        }
        let app = (session["app"] as? String ?? "").lowercased()
        let hits = windows.filter { candidate in
            let owner = candidate.owningApplication?.applicationName.lowercased() ?? ""
            let bundle = candidate.owningApplication?.bundleIdentifier.lowercased() ?? ""
            let size = candidate.frame
            guard size.width >= 160, size.height >= 160 else { return false }
            if app == owner { return true }
            if owner.contains(app) || app.contains(owner) { return true }
            if app.contains("simulator") && (owner.contains("simulator") || bundle.contains("iphonesimulator")) {
                return true
            }
            return false
        }
        return hits.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    }

    private static func appKitFrame(for quartz: CGRect) -> NSRect {
        let height = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        return NSRect(
            x: quartz.origin.x,
            y: height - quartz.origin.y - quartz.height,
            width: quartz.width,
            height: quartz.height
        )
    }

    private static func clampedHotspot(session: [String: Any], windowFrame: NSRect) -> NSPoint {
        var local = NSPoint(x: 22, y: windowFrame.height - 48)
        if let cursor = session["cursor"] as? [String: Any],
           let x = double(cursor["x"]),
           let y = double(cursor["y"]) {
            local = NSPoint(x: x - windowFrame.minX, y: y - windowFrame.minY)
        }
        return clamp(local, windowFrame: windowFrame)
    }

    private static func clamp(_ local: NSPoint, windowFrame: NSRect) -> NSPoint {
        let inset: CGFloat = 10
        let arrowWidth: CGFloat = 24
        let arrowHeight: CGFloat = 32
        let minX = inset
        let maxX = max(minX, windowFrame.width - arrowWidth - inset)
        let minY = arrowHeight + inset
        let maxY = max(minY, windowFrame.height - inset)
        return NSPoint(
            x: min(max(local.x, minX), maxX),
            y: min(max(local.y, minY), maxY)
        )
    }

    private static func double(_ value: Any?) -> Double? {
        if value is NSNull { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        return nil
    }

    private static func color(from hex: String) -> NSColor {
        var value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        var int: UInt64 = 0
        Scanner(string: value).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
}
