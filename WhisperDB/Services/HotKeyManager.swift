import AppKit
import Carbon
import HotKey

final class HotKeyManager {
    private var hotKey: HotKey?
    private var historyHotKey: HotKey?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?

    private var optionHeld = false
    private var otherKeyPressedWhileOption = false

    var onToggle: (() -> Void)?
    /// Fires on a clean Option-key tap (Option pressed and released with no other key
    /// in between). The caller decides what it means — stop recording, or dismiss the
    /// review panel.
    var onOptionTap: (() -> Void)?
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

    /// Enable/disable the Option-key-alone monitor. While enabled, `onOptionTap` fires
    /// only on an Option key release when no other key was pressed in between — so
    /// Option+Tab (space switch) does not trigger it. Stays enabled across both the
    /// recording and review phases; disabled only once the panel is dismissed.
    func setListening(_ listening: Bool) {
        if listening {
            optionHeld = false
            otherKeyPressedWhileOption = false

            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self = self else { return }
                let optionNow = event.modifierFlags.contains(.option)
                let otherModifiers = event.modifierFlags
                    .intersection([.shift, .command, .control, .function])

                if optionNow && !self.optionHeld {
                    self.optionHeld = true
                    self.otherKeyPressedWhileOption = !otherModifiers.isEmpty
                } else if optionNow && self.optionHeld {
                    if !otherModifiers.isEmpty {
                        self.otherKeyPressedWhileOption = true
                    }
                } else if !optionNow && self.optionHeld {
                    let cleanRelease =
                        !self.otherKeyPressedWhileOption && otherModifiers.isEmpty
                    self.optionHeld = false
                    if cleanRelease {
                        self.onOptionTap?()
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
