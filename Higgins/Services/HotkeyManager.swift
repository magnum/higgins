import Foundation
import Carbon
import AppKit

/// Registers the global shortcut ⌃⌥⌘C using a Carbon hot key.
///
/// Unlike `NSEvent.addGlobalMonitorForEvents`, a Carbon hot key is registered
/// directly with the window server and therefore fires **without** requiring
/// Accessibility permission. This lets the shortcut work immediately; the
/// Accessibility permission is only requested later, on first actual use,
/// when the app needs to simulate Cmd+C / Cmd+V to read and replace text.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
        if RuntimeEnvironment.isRunningTests {
            log("Skipping hotkey registration during tests")
        } else {
            registerHotkey()
        }
    }

    deinit {
        log("Cleaning up HotkeyManager")
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func registerHotkey() {
        log("Registering global hotkey ⌃⌥⌘C via Carbon (no accessibility required to detect it)")

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotkey()
                return noErr
            },
            1, &eventType, selfPtr, &eventHandler
        )

        if handlerStatus != noErr {
            log("Failed to install hot key event handler (status: \(handlerStatus))", type: .error)
            return
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("HGNS"), id: 1)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let keyCode = UInt32(0x08)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            log("Global hotkey ⌃⌥⌘C registered successfully")
        } else {
            log("Failed to register global hotkey (status: \(status))", type: .error)
        }
    }

    private func handleHotkey() {
        log("Global hotkey ⌃⌥⌘C detected")
        DispatchQueue.main.async { [weak self] in
            self?.callback()
        }
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + FourCharCode(scalar.value & 0xFF)
        }
        return result
    }
}
