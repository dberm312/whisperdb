import AppKit
import SwiftUI

/// A borderless, non-activating floating panel that shows live transcription as
/// the user speaks. Unlike the history/organize windows it never changes the
/// app's activation policy or steals key focus — so dictation keeps flowing into
/// whatever app the user is actually typing in.
///
/// The panel auto-fits its height to the content (so long to-do lists are fully
/// visible without scrolling) up to a screen-relative cap, and is also user-resizable
/// by dragging its edges. A manual drag overrides auto-fit for the rest of the session;
/// `resetAutoFit()` (called when a new recording starts) restores auto-fitting.
@MainActor
final class LiveTranscriptionWindowController: NSObject, NSWindowDelegate {
    static let shared = LiveTranscriptionWindowController()

    private var panel: NSPanel?

    private let defaultWidth: CGFloat = 560
    private let minHeight: CGFloat = 160
    private let edgeMargin: CGFloat = 16
    private let topMargin: CGFloat = 8

    private static let widthKey = "livePanelWidth"

    /// Once the user drags to resize, we stop auto-fitting until the next recording.
    private var manualHeight: CGFloat?
    /// Set while we resize the panel ourselves, so `windowDidResize` ignores it.
    private var isAutoResizing = false

    private var currentWidth: CGFloat {
        let saved = UserDefaults.standard.double(forKey: Self.widthKey)
        return saved > 0 ? saved : defaultWidth
    }

    private var maxHeight: CGFloat {
        guard let screen = NSScreen.main else { return 800 }
        return screen.visibleFrame.height * 0.85
    }

    func show(with manager: TranscriptionManager) {
        if let panel {
            position(panel)
            panel.orderFrontRegardless()
            return
        }

        let width = currentWidth
        let view = LiveTranscriptionView(manager: manager) { [weak self] height in
            self?.applyContentHeight(height)
        }
        let hosting = NSHostingController(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: minHeight),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        // Assigning contentViewController resizes the panel to the SwiftUI view's
        // fitting size (which collapses to near-zero with a flexible frame), so
        // pin the size back explicitly or the panel renders invisibly.
        panel.setContentSize(NSSize(width: width, height: minHeight))
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

    /// Restores auto-fitting (called when a new recording begins) so each session
    /// starts sizing itself to the content again.
    func resetAutoFit() {
        manualHeight = nil
    }

    /// Resizes the panel to fit the reported natural content height, clamped to
    /// `[minHeight, maxHeight]`, growing downward from a fixed top edge. No-op once
    /// the user has manually resized this session.
    private func applyContentHeight(_ height: CGFloat) {
        guard manualHeight == nil, let panel else { return }
        let target = min(max(height, minHeight), maxHeight)
        let frame = panel.frame
        guard abs(frame.height - target) > 0.5 else { return }

        // Keep the top edge fixed: the panel grows/shrinks downward.
        let newOrigin = NSPoint(x: frame.origin.x, y: frame.maxY - target)
        let newFrame = NSRect(x: newOrigin.x, y: newOrigin.y, width: frame.width, height: target)

        isAutoResizing = true
        panel.setFrame(newFrame, display: true, animate: false)
        isAutoResizing = false
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        // Top-right, just below the menu bar / near the status bar item.
        let visible = screen.visibleFrame
        let x = visible.maxX - panel.frame.width - edgeMargin
        let y = visible.maxY - panel.frame.height - topMargin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard !isAutoResizing, let panel else { return }
        // User-driven resize: lock in their height and remember the width.
        manualHeight = panel.frame.height
        UserDefaults.standard.set(panel.frame.width, forKey: Self.widthKey)
    }
}
