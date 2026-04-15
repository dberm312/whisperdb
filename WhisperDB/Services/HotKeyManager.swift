import Carbon
import HotKey
import AppKit

final class HotKeyManager {
    private var hotKey: HotKey?
    private var historyHotKey: HotKey?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?

    private var optionHeld = false
    private var otherKeyPressedWhileOption = false

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
    /// Stop fires only on Option key release when no other key was pressed
    /// in between — so Option+Tab (space switch) does not stop recording.
    func setRecording(_ isRecording: Bool) {
        if isRecording {
            optionHeld = false
            otherKeyPressedWhileOption = false

            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self = self else { return }
                let optionNow = event.modifierFlags.contains(.option)
                if optionNow && !self.optionHeld {
                    self.optionHeld = true
                    self.otherKeyPressedWhileOption = false
                } else if !optionNow && self.optionHeld {
                    let cleanRelease = !self.otherKeyPressedWhileOption &&
                        event.modifierFlags.intersection([.shift, .command, .control, .function]).isEmpty
                    self.optionHeld = false
                    if cleanRelease {
                        self.onStopRecording?()
                    }
                }
            }

            keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                guard let self = self, self.optionHeld else { return }
                self.otherKeyPressedWhileOption = true
            }
        } else {
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownMonitor = nil
            }
            optionHeld = false
            otherKeyPressedWhileOption = false
        }
    }

    deinit {
        hotKey = nil
        historyHotKey = nil
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
