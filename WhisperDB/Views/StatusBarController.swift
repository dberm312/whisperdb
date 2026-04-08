import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem!
    private var transcriptionManager: TranscriptionManager!
    private var stateObservation: NSKeyValueObservation?
    private var cancellables: [Any] = []
    private static let audioLineSegments: [(x: CGFloat, y1: CGFloat, y2: CGFloat)] = [
        (2, 10, 13),
        (6, 6, 17),
        (10, 3, 21),
        (14, 8, 15),
        (18, 5, 18),
        (22, 10, 13),
    ]

    func setup(with manager: TranscriptionManager) {
        self.transcriptionManager = manager

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: .idle, audioLevel: 0)
        buildMenu()

        // Observe state changes to update icon
        // Using a timer to poll state since @Published doesn't easily bridge to NSStatusItem
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateIcon(for: self.transcriptionManager.state, audioLevel: self.transcriptionManager.recorder.audioLevel)
                self.buildMenu()
            }
        }
    }

    private func updateIcon(for state: RecordingState, audioLevel: Float) {
        guard let button = statusItem?.button else { return }

        switch state {
        case .idle:
            button.image = makeAudioLinesIcon(size: 18, strokeWidth: 1.5, color: .controlTextColor, isTemplate: true)
        case .recording:
            button.image = makeListeningIcon(size: 18, strokeWidth: 1.7, audioLevel: audioLevel)
        case .processing:
            button.image = makeAudioLinesIcon(
                size: 18,
                strokeWidth: 1.5,
                color: NSColor(calibratedWhite: 0.74, alpha: 1),
                isTemplate: false
            )
        }
    }

    private func makeAudioLinesIcon(size: CGFloat, strokeWidth: CGFloat, color: NSColor, isTemplate: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = size / 24.0
            color.setStroke()
            Self.drawAudioLines(scale: scale, strokeWidth: strokeWidth)
            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    private func makeListeningIcon(size: CGFloat, strokeWidth: CGFloat, audioLevel: Float) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = size / 24.0
            let level = min(max(CGFloat(audioLevel), 0), 1)
            let opacity = 0.78 + 0.22 * level
            let inset = 0.25 * scale
            let backgroundRect = rect.insetBy(dx: inset, dy: inset)
            let backgroundPath = NSBezierPath(
                roundedRect: backgroundRect,
                xRadius: 4 * scale,
                yRadius: 4 * scale
            )
            NSColor.systemRed.withAlphaComponent(opacity).setFill()
            backgroundPath.fill()

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSColor.clear.setStroke()
            Self.drawAudioLines(scale: scale, strokeWidth: strokeWidth)
            NSGraphicsContext.restoreGraphicsState()

            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawAudioLines(scale: CGFloat, strokeWidth: CGFloat) {
        for line in Self.audioLineSegments {
            let path = NSBezierPath()
            path.lineWidth = strokeWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: line.x * scale, y: (24 - line.y1) * scale))
            path.line(to: NSPoint(x: line.x * scale, y: (24 - line.y2) * scale))
            path.stroke()
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Status line
        let statusText: String
        switch transcriptionManager.state {
        case .idle:
            statusText = "WhisperDB — Ready"
        case .recording:
            statusText = "WhisperDB — Listening..."
        case .processing:
            statusText = "WhisperDB — Processing..."
        }
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if
            let elapsedTime = transcriptionManager.recordingElapsedTime,
            elapsedTime >= transcriptionManager.recordingTimerVisibleAfter
        {
            let cappedElapsedTime = min(elapsedTime, transcriptionManager.maxRecordingDuration)
            let timerText = "Recording: \(formatDuration(cappedElapsedTime)) / \(formatDuration(transcriptionManager.maxRecordingDuration))"
            let timerItem = NSMenuItem(title: timerText, action: nil, keyEquivalent: "")
            timerItem.isEnabled = false
            menu.addItem(timerItem)
        }

        // Error display
        if let error = transcriptionManager.lastError {
            let errorItem = NSMenuItem(title: "⚠ \(error)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Hotkey hints
        let hintItem = NSMenuItem(title: "⌥ Space to toggle recording", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        let historyHintItem = NSMenuItem(title: "⇧⌥ Space to open history", action: nil, keyEquivalent: "")
        historyHintItem.isEnabled = false
        menu.addItem(historyHintItem)

        menu.addItem(NSMenuItem.separator())

        // History
        if transcriptionManager.history.isEmpty {
            let emptyItem = NSMenuItem(title: "No transcriptions yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            let headerItem = NSMenuItem(title: "Recent Transcriptions", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)

            for (index, transcription) in transcriptionManager.history.prefix(10).enumerated() {
                let title = "\(transcription.displayText)  (\(transcription.timeAgo))"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

                let submenu = NSMenu()

                let copyItem = NSMenuItem(title: "Copy", action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                copyItem.target = self
                copyItem.tag = index
                submenu.addItem(copyItem)

                let organizeItem = NSMenuItem(title: "Organize", action: #selector(organizeHistoryItem(_:)), keyEquivalent: "")
                organizeItem.target = self
                organizeItem.tag = index
                submenu.addItem(organizeItem)

                item.submenu = submenu
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())

            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit WhisperDB", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < transcriptionManager.history.count else { return }
        transcriptionManager.copyFromHistory(transcriptionManager.history[index])
    }

    @objc private func organizeHistoryItem(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < transcriptionManager.history.count else { return }
        OrganizeWindowController.shared.openWindow(for: transcriptionManager.history[index])
    }

    @objc private func clearHistory() {
        transcriptionManager.clearHistory()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
