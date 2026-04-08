import AppKit
import Carbon
import os

enum ClipboardService {
    private static let logger = Logger(subsystem: "com.whisperdb.app", category: "clipboard")

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Simulates Cmd+V to paste into the frontmost app.
    @discardableResult
    static func paste() -> Bool {
        guard ensureAccessibilityPermission(prompt: false) else {
            logger.warning("Paste skipped because Accessibility permission is not granted")
            return false
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            )
        else {
            logger.error("Failed to create Cmd+V key events")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        usleep(50_000)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    /// Checks (and optionally prompts for) Accessibility permission.
    @discardableResult
    static func ensureAccessibilityPermission(prompt: Bool = true) -> Bool {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        )
        if !trusted {
            logger.warning("Accessibility permission not granted")
        }
        return trusted
    }
}
