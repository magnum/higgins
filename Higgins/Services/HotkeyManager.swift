import Foundation
import Carbon
import AppKit

/// A global keyboard shortcut: a virtual key code plus modifier flags.
struct HotkeyShortcut: Codable, Equatable {
    /// Carbon virtual key code (`kVK_*`).
    let keyCode: UInt32
    /// Raw value of the device-independent `NSEvent.ModifierFlags`.
    let modifierFlags: UInt
    /// Human-readable key, captured from the keyboard layout when recorded.
    let keyLabel: String

    /// The original ⌃⌥⌘C shortcut.
    static let `default` = HotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: [.control, .option, .command],
        keyLabel: "C"
    )

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection(Self.supportedModifiers).rawValue
        self.keyLabel = keyLabel
    }

    /// Builds a shortcut from a key-down event, or `nil` for Return/Enter,
    /// which is reserved to confirm the recording.
    init?(event: NSEvent) {
        let keyCode = Int(event.keyCode)
        guard keyCode != kVK_Return, keyCode != kVK_ANSI_KeypadEnter else { return nil }
        self.init(
            keyCode: UInt32(keyCode),
            modifiers: event.modifierFlags,
            keyLabel: Self.label(for: keyCode, event: event)
        )
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    var displayString: String {
        Self.symbols(for: modifiers) + keyLabel
    }

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    static let supportedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// Modifier symbols in the order macOS displays them.
    static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11",
        kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    private static func label(for keyCode: Int, event: NSEvent) -> String {
        if let label = specialKeyLabels[keyCode] {
            return label
        }
        // Use the unmodified character so ⇧1 shows "1" and ⌥C shows "C".
        let character = event.characters(byApplyingModifiers: [])
            ?? event.charactersIgnoringModifiers
            ?? ""
        let trimmed = character.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Key \(keyCode)" : trimmed.uppercased()
    }
}

/// Registers the global shortcut using a Carbon hot key.
///
/// Unlike `NSEvent.addGlobalMonitorForEvents`, a Carbon hot key is registered
/// directly with the window server and therefore fires **without** requiring
/// Accessibility permission. This lets the shortcut work immediately; the
/// Accessibility permission is only requested later, on first actual use,
/// when the app needs to simulate Cmd+C / Cmd+V to read and replace text.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var shortcut: HotkeyShortcut
    private let callback: () -> Void

    init(shortcut: HotkeyShortcut, callback: @escaping () -> Void) {
        self.shortcut = shortcut
        self.callback = callback
        if RuntimeEnvironment.isRunningTests {
            log("Skipping hotkey registration during tests")
        } else {
            installEventHandler()
            registerHotkey()
        }
    }

    deinit {
        log("Cleaning up HotkeyManager")
        unregisterHotkey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// Replaces the registered shortcut with a new one.
    func update(shortcut: HotkeyShortcut) {
        self.shortcut = shortcut
        unregisterHotkey()
        registerHotkey()
    }

    /// Temporarily releases the shortcut, e.g. while the user records a new one.
    func suspend() {
        unregisterHotkey()
    }

    /// Re-registers the shortcut after `suspend()`.
    func resume() {
        guard hotKeyRef == nil else { return }
        registerHotkey()
    }

    private func installEventHandler() {
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
        }
    }

    private func registerHotkey() {
        guard eventHandler != nil else { return }
        log("Registering global hotkey \(shortcut.displayString) via Carbon (no accessibility required to detect it)")

        let hotKeyID = EventHotKeyID(signature: fourCharCode("HGNS"), id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            log("Global hotkey \(shortcut.displayString) registered successfully")
        } else {
            hotKeyRef = nil
            log("Failed to register global hotkey \(shortcut.displayString) (status: \(status))", type: .error)
        }
    }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func handleHotkey() {
        log("Global hotkey \(shortcut.displayString) detected")
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
