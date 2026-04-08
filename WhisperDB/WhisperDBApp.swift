import AppKit
import SwiftUI

@main
struct WhisperDBApp {
    static func main() {
        let app = NSApplication.shared
        // Menu bar only — no dock icon
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var transcriptionManager: TranscriptionManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        transcriptionManager = TranscriptionManager()
        statusBarController = StatusBarController()
        statusBarController.setup(with: transcriptionManager)
    }
}
