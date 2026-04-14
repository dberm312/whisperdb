import AppKit

enum ClipboardService {
    static func clear() {
        NSPasteboard.general.clearContents()
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
