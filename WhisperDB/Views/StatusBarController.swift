import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, ObservableObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu?
    private var transcriptionManager: TranscriptionManager!
    private var previousIconState: RecordingState?
    private var previousAudioLevel: Float = 0
    private var previousMenuSnapshot: (RecordingState, String?, Int, TimeInterval?, String) = (.idle, nil, 0, nil, "")
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
        let menu = NSMenu()
        menu.delegate = self
        self.menu = menu
        statusItem.menu = menu
        buildMenu()

        // Observe state changes to update icon
        // Using a timer to poll state since @Published doesn't easily bridge to NSStatusItem
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let state = self.transcriptionManager.state
                let audioLevel = self.transcriptionManager.recorder.audioLevel
                self.updateIcon(for: state, audioLevel: audioLevel)
                self.rebuildMenuIfNeeded()
            }
        }
    }

    private func updateIcon(for state: RecordingState, audioLevel: Float) {
        guard let button = statusItem?.button else { return }

        switch state {
        case .idle:
            button.image = makeAudioLinesIcon(size: 18, strokeWidth: 1.5, color: .controlTextColor, isTemplate: true)
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
        case .recording:
            button.image = makeListeningIcon(size: 18, strokeWidth: 1.7, audioLevel: audioLevel)
            button.attributedTitle = NSAttributedString(string: "")
            if let elapsed = transcriptionManager.recordingElapsedTime {
                button.title = " \(formatDuration(elapsed))"
            }
        case .processing:
            button.image = makeAudioLinesIcon(
                size: 18,
                strokeWidth: 1.5,
                color: NSColor(calibratedWhite: 0.74, alpha: 1),
                isTemplate: false
            )
            button.attributedTitle = NSAttributedString(
                string: " Processing…",
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.menuBarFont(ofSize: 0)
                ]
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
        let level = min(max(CGFloat(audioLevel), 0), 1)
        let opacity = 0.78 + 0.22 * level
        let color = NSColor.systemRed.withAlphaComponent(opacity)
        return makeAudioLinesIcon(size: size, strokeWidth: strokeWidth, color: color, isTemplate: false)
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

    private func rebuildMenuIfNeeded() {
        let currentSnapshot = (
            transcriptionManager.state,
            transcriptionManager.lastError,
            transcriptionManager.history.count,
            transcriptionManager.recordingElapsedTime,
            transcriptionManager.microphoneManager.menuSignature
        )
        let prev = previousMenuSnapshot
        let changed = currentSnapshot.0 != prev.0
            || currentSnapshot.1 != prev.1
            || currentSnapshot.2 != prev.2
            || Int(currentSnapshot.3 ?? -1) != Int(prev.3 ?? -1)
            || currentSnapshot.4 != prev.4
        guard changed else { return }
        previousMenuSnapshot = currentSnapshot
        buildMenu()
    }

    private func buildMenu() {
        transcriptionManager.microphoneManager.refreshDevices()
        previousMenuSnapshot = (
            transcriptionManager.state,
            transcriptionManager.lastError,
            transcriptionManager.history.count,
            transcriptionManager.recordingElapsedTime,
            transcriptionManager.microphoneManager.menuSignature
        )

        guard let menu else { return }
        menu.removeAllItems()

        // Status line
        let statusText: String
        switch transcriptionManager.state {
        case .idle:
            statusText = "WhisperDB — Ready"
        case .recording:
            statusText = "WhisperDB — Listening..."
        case .processing:
            statusText = "WhisperDB — Processing…"
        }
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if let elapsedTime = transcriptionManager.recordingElapsedTime {
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

        if let warning = transcriptionManager.microphoneManager.selectionWarning {
            let warningItem = NSMenuItem(title: "⚠ \(warning)", action: nil, keyEquivalent: "")
            warningItem.isEnabled = false
            menu.addItem(warningItem)
        }

        menu.addItem(NSMenuItem.separator())

        addMicrophoneMenu(to: menu)
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

                submenu.addItem(NSMenuItem.separator())

                let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteHistoryItem(_:)), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.tag = index
                submenu.addItem(deleteItem)

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
    }

    private func addMicrophoneMenu(to menu: NSMenu) {
        let microphoneItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let microphoneSubmenu = NSMenu()
        let microphoneManager = transcriptionManager.microphoneManager
        let isRecording = transcriptionManager.state == .recording

        if isRecording {
            let recordingHintItem = NSMenuItem(title: "Change after recording stops", action: nil, keyEquivalent: "")
            recordingHintItem.isEnabled = false
            microphoneSubmenu.addItem(recordingHintItem)
            microphoneSubmenu.addItem(NSMenuItem.separator())
        }

        let systemDefaultName = microphoneManager.currentSystemDefaultName ?? "No default microphone"
        let systemDefaultItem = NSMenuItem(
            title: "System Default (\(systemDefaultName))",
            action: #selector(selectSystemDefaultMicrophone),
            keyEquivalent: ""
        )
        systemDefaultItem.target = self
        systemDefaultItem.isEnabled = !isRecording
        systemDefaultItem.state = microphoneManager.selectedDeviceUID == nil ? .on : .off
        microphoneSubmenu.addItem(systemDefaultItem)

        if !microphoneManager.devices.isEmpty {
            microphoneSubmenu.addItem(NSMenuItem.separator())
        }

        for device in microphoneManager.devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.isEnabled = !isRecording
            item.state = microphoneManager.selectedDeviceUID == device.uid ? .on : .off
            microphoneSubmenu.addItem(item)
        }

        if microphoneManager.devices.isEmpty {
            let noDevicesItem = NSMenuItem(title: "No microphones found", action: nil, keyEquivalent: "")
            noDevicesItem.isEnabled = false
            microphoneSubmenu.addItem(noDevicesItem)
        }

        microphoneItem.submenu = microphoneSubmenu
        menu.addItem(microphoneItem)
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

    @objc private func deleteHistoryItem(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < transcriptionManager.history.count else { return }
        transcriptionManager.deleteFromHistory(at: index)
    }

    @objc private func clearHistory() {
        transcriptionManager.clearHistory()
    }

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
    }

    @objc private func selectSystemDefaultMicrophone() {
        guard transcriptionManager.state != .recording else { return }
        transcriptionManager.microphoneManager.selectSystemDefault()
        buildMenu()
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard transcriptionManager.state != .recording else { return }
        guard let uid = sender.representedObject as? String else { return }
        transcriptionManager.microphoneManager.selectDevice(uid: uid)
        buildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
