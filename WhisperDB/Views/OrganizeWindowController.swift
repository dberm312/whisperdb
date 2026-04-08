import AppKit
import SwiftUI
import WhisperDBKit

@MainActor
final class OrganizeWindowController: NSObject, NSWindowDelegate {
    static let shared = OrganizeWindowController()

    private(set) var openWindows: [NSWindow] = []

    var hasOpenWindows: Bool { !openWindows.isEmpty }

    func openWindow(for transcription: Transcription) {
        let viewModel = OrganizeViewModel(transcription: transcription)
        let view = OrganizeView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Organize — WhisperDB"
        window.setContentSize(NSSize(width: 600, height: 500))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.delegate = self
        window.center()

        // Show in dock so the window can receive focus
        if openWindows.isEmpty {
            NSApp.setActivationPolicy(.regular)
        }

        openWindows.append(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        openWindows.removeAll { $0 === closingWindow }

        if openWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
