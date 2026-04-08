import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = HistoryWindowController()

    private(set) var window: NSWindow?

    func openWindow(with manager: TranscriptionManager) {
        // If window already exists, just bring it to front
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = HistoryView(manager: manager)
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dictation History — WhisperDB"
        window.setContentSize(NSSize(width: 600, height: 500))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.delegate = self
        window.center()

        self.window = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil

        // Only go back to accessory if no organize windows are open either
        if OrganizeWindowController.shared.hasOpenWindows == false {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
