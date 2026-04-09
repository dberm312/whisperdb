import AppKit

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
        setupMainMenu()
        transcriptionManager = TranscriptionManager()
        statusBarController = StatusBarController()
        statusBarController.setup(with: transcriptionManager)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: "WhisperDB", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "WhisperDB")
        appMenu.addItem(
            NSMenuItem(
                title: "Quit WhisperDB",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        let closeWindowItem = NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeWindowItem.target = nil
        windowMenu.addItem(closeWindowItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
