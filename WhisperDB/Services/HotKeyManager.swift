import AppKit
import Carbon
import HotKey

final class HotKeyManager {
    private var hotKey: HotKey?
    private var historyHotKey: HotKey?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyDownMonitor: Any?

    private var optionHeld = false
    private var otherKeyPressedWhileOption = false

    var onToggle: (() -> Void)?
    var onOptionReleaseWhileRecording: (() -> Void)?
    var onOpenHistory: (() -> Void)?

    init() {
        // Option+Space — start or stop recording
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

    /// Enable/disable the Option-key-alone monitor while recording.
    /// The callback fires only on Option key release when no other key was pressed
    /// in between — so Option+Tab (space switch) does not trigger it.
    func setRecording(_ isRecording: Bool) {
        if isRecording {
            optionHeld = false
            otherKeyPressedWhileOption = false

            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
            }

            keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                self?.handleKeyDown()
            }

            // Local monitors fire while WhisperDB is the active app; global monitors fire while it isn't.
            // Both are needed because the Realtime panel brings WhisperDB to the foreground.
            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
                return event
            }

            localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown()
                return event
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
            if let monitor = localFlagsMonitor {
                NSEvent.removeMonitor(monitor)
                localFlagsMonitor = nil
            }
            if let monitor = localKeyDownMonitor {
                NSEvent.removeMonitor(monitor)
                localKeyDownMonitor = nil
            }
            optionHeld = false
            otherKeyPressedWhileOption = false
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let optionNow = event.modifierFlags.contains(.option)
        let otherModifiers = event.modifierFlags
            .intersection([.shift, .command, .control, .function])

        if optionNow && !optionHeld {
            optionHeld = true
            otherKeyPressedWhileOption = !otherModifiers.isEmpty
        } else if optionNow && optionHeld {
            if !otherModifiers.isEmpty {
                otherKeyPressedWhileOption = true
            }
        } else if !optionNow && optionHeld {
            let cleanRelease = !otherKeyPressedWhileOption && otherModifiers.isEmpty
            optionHeld = false
            if cleanRelease {
                onOptionReleaseWhileRecording?()
            }
        }
    }

    private func handleKeyDown() {
        guard optionHeld else { return }
        otherKeyPressedWhileOption = true
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
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
