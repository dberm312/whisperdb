import Carbon
import HotKey
import AppKit

final class HotKeyManager {
    private var hotKey: HotKey?
    private var historyHotKey: HotKey?
    private var flagsMonitor: Any?

    var onToggle: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onOpenHistory: (() -> Void)?

    init() {
        // Option+Space — toggle recording
        hotKey = HotKey(key: .space, modifiers: [.option])
        hotKey?.keyDownHandler = { [weak self] in
            self?.onToggle?()
        }

        // Shift+Option+Space — open history window
        historyHotKey = HotKey(key: .space, modifiers: [.shift, .option])
        historyHotKey?.keyDownHandler = { [weak self] in
            self?.onOpenHistory?()
        }
    }

    /// Enable/disable the Option-key-alone monitor for stopping recording.
    func setRecording(_ isRecording: Bool) {
        if isRecording {
            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                // Option key pressed (not as part of Option+Space, which is handled by HotKey)
                if event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.shift) {
                    self?.onStopRecording?()
                }
            }
        } else {
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
        }
    }

    deinit {
        hotKey = nil
        historyHotKey = nil
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
