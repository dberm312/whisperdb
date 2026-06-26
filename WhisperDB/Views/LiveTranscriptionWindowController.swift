import AppKit
import SwiftUI

/// A borderless, non-activating floating panel that shows live transcription as
/// the user speaks. Unlike the history/organize windows it never changes the
/// app's activation policy or steals key focus — so dictation keeps flowing into
/// whatever app the user is actually typing in.
@MainActor
final class LiveTranscriptionWindowController: NSObject, NSWindowDelegate {
    static let shared = LiveTranscriptionWindowController()

    private var panel: NSPanel?

    private let panelWidth: CGFloat = 560
    private let panelHeight: CGFloat = 360
    private let edgeMargin: CGFloat = 16
    private let topMargin: CGFloat = 8

    func show(with manager: TranscriptionManager) {
        if let panel {
            position(panel)
            panel.orderFrontRegardless()
            return
        }

        let view = LiveTranscriptionView(manager: manager)
        let hosting = NSHostingController(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        // Assigning contentViewController resizes the panel to the SwiftUI view's
        // fitting size (which collapses to near-zero with a flexible frame), so
        // pin the size back explicitly or the panel renders invisibly.
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.delegate = self

        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        // Top-right, just below the menu bar / near the status bar item.
        let visible = screen.visibleFrame
        let x = visible.maxX - panelWidth - edgeMargin
        let y = visible.maxY - panelHeight - topMargin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
