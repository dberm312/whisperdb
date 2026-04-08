import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem!
    private var transcriptionManager: TranscriptionManager!
    private var stateObservation: NSKeyValueObservation?
    private var cancellables: [Any] = []

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
            button.image = makeCaptionsIcon(size: 18, strokeWidth: 1.5, color: .controlTextColor)
        case .recording:
            button.image = makeRecordingIcon(size: 18, strokeWidth: 1.5, audioLevel: audioLevel)
        case .processing:
            button.image = makeCaptionsIcon(size: 18, strokeWidth: 1.5, color: .secondaryLabelColor)
        }
    }

    /// Draws the Lucide "captions" icon: rounded rect with four caption-bar lines inside.
    /// SVG source (24x24 viewBox):
    ///   <rect width="18" height="14" x="3" y="5" rx="2"/>
    ///   <path d="M7 15h4  M15 15h2  M7 11h2  M13 11h4"/>
    private func makeCaptionsIcon(size: CGFloat, strokeWidth: CGFloat, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = size / 24.0
            color.setStroke()

            // Rounded rectangle frame
            let rrRect = NSRect(x: 3 * scale, y: (24 - 5 - 14) * scale, width: 18 * scale, height: 14 * scale)
            let rr = NSBezierPath(roundedRect: rrRect, xRadius: 2 * scale, yRadius: 2 * scale)
            rr.lineWidth = strokeWidth
            rr.stroke()

            // Caption bars (SVG y-coords flipped because AppKit origin is bottom-left)
            let lines: [(x1: CGFloat, x2: CGFloat, y: CGFloat)] = [
                (7, 11, 24 - 15),   // M7 15h4
                (15, 17, 24 - 15),  // M15 15h2
                (7, 9, 24 - 11),    // M7 11h2
                (13, 17, 24 - 11),  // M13 11h4
            ]

            for line in lines {
                let path = NSBezierPath()
                path.lineWidth = strokeWidth
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: line.x1 * scale, y: line.y * scale))
                path.line(to: NSPoint(x: line.x2 * scale, y: line.y * scale))
                path.stroke()
            }

            return true
        }
        image.isTemplate = (color == .controlTextColor) // template mode only for idle (adapts to dark/light)
        return image
    }

    /// Recording icon: red circle that pulses with audio level, with caption bars as transparent cutouts.
    private func makeRecordingIcon(size: CGFloat, strokeWidth: CGFloat, audioLevel: Float) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = size / 24.0
            let level = CGFloat(audioLevel)

            // Pulsing red circle — base opacity 0.6, pulses to 1.0 with audio
            let circleOpacity = 0.6 + 0.4 * level
            let circleColor = NSColor.systemRed.withAlphaComponent(circleOpacity)

            // Circle fills the icon area with slight padding
            let inset: CGFloat = 1 * scale
            let circleRect = rect.insetBy(dx: inset, dy: inset)

            // Draw the red circle
            let circlePath = NSBezierPath(ovalIn: circleRect)
            circleColor.setFill()
            circlePath.fill()

            // Draw caption bars as transparent cutouts using .clear blend mode
            NSGraphicsContext.current?.compositingOperation = .clear

            // Caption bars (same pattern as the captions icon)
            let lines: [(x1: CGFloat, x2: CGFloat, y: CGFloat)] = [
                (7, 11, 24 - 15),
                (15, 17, 24 - 15),
                (7, 9, 24 - 11),
                (13, 17, 24 - 11),
            ]

            for line in lines {
                let path = NSBezierPath()
                path.lineWidth = strokeWidth
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: line.x1 * scale, y: line.y * scale))
                path.line(to: NSPoint(x: line.x2 * scale, y: line.y * scale))
                path.stroke()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Status line
        let statusText: String
        switch transcriptionManager.state {
        case .idle:
            statusText = "WhisperDB — Ready"
        case .recording:
            statusText = "WhisperDB — Recording..."
        case .processing:
            statusText = "WhisperDB — Transcribing..."
        }
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

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
