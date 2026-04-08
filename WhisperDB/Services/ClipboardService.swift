import AppKit

enum ClipboardService {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Simulates Cmd+V via AppleScript to paste into the frontmost app.
    /// This avoids the Accessibility permission requirement that CGEvent needs.
    static func paste() {
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
    }
}
