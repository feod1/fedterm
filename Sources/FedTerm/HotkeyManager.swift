import Carbon.HIToolbox
import AppKit

/// Global hotkey via Carbon RegisterEventHotKey — works without Accessibility permissions.
/// Option+Space by default, reassignable in settings.
final class HotkeyManager {
    static let shared = HotkeyManager()

    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = UInt32(optionKey)

    var handler: (() -> Void)?

    private(set) var keyCode: UInt32 = HotkeyManager.defaultKeyCode
    private(set) var modifiers: UInt32 = HotkeyManager.defaultModifiers

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// Registers the shortcut. false — the system refused it (taken by another app);
    /// in that case we restore the previous one.
    @discardableResult
    func register(keyCode newCode: UInt32, modifiers newModifiers: UInt32) -> Bool {
        let previousCode = keyCode
        let previousModifiers = modifiers

        installEventHandlerIfNeeded()
        unregisterHotKey()

        let hotKeyID = EventHotKeyID(signature: OSType(0x4654524D), id: 1) // 'FTRM'
        let status = RegisterEventHotKey(
            newCode, newModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr, hotKeyRef != nil else {
            hotKeyRef = nil
            if previousCode != newCode || previousModifiers != newModifiers {
                RegisterEventHotKey(
                    previousCode, previousModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
                )
            }
            return false
        }
        keyCode = newCode
        modifiers = newModifiers
        return true
    }

    /// Registers the shortcut saved in settings.
    @discardableResult
    func registerFromSettings() -> Bool {
        register(keyCode: SettingsStore.shared.hotKeyCode, modifiers: SettingsStore.shared.hotKeyModifiers)
    }

    /// Temporarily removes the hotkey — needed while recording a new shortcut, otherwise Carbon
    /// would intercept the keystroke before the recorder sees it.
    func suspend() {
        unregisterHotKey()
    }

    func unregister() {
        unregisterHotKey()
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        eventHandlerRef = nil
    }

    private func unregisterHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.handler?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    deinit { unregister() }
}

// MARK: - Shortcut presentation

/// Turns keyCode and modifiers into a human-readable form (⌥Space, ⌃⌘K, F13 …)
/// and converts NSEvent flags to Carbon ones.
enum HotkeyFormatter {
    /// Modifier symbols in the system order ⌃⌥⇧⌘.
    static func modifierSymbols(_ carbonFlags: UInt32) -> String {
        var out = ""
        if carbonFlags & UInt32(controlKey) != 0 { out += "⌃" }
        if carbonFlags & UInt32(optionKey) != 0 { out += "⌥" }
        if carbonFlags & UInt32(shiftKey) != 0 { out += "⇧" }
        if carbonFlags & UInt32(cmdKey) != 0 { out += "⌘" }
        return out
    }

    static func display(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierSymbols(modifiers) + keyName(keyCode)
    }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    /// Keys we don't mind claiming outright — they can be assigned without modifiers.
    static func isStandaloneSafe(keyCode: UInt32) -> Bool {
        functionKeys[UInt16(keyCode)] != nil
    }

    static func keyName(_ keyCode: UInt32) -> String {
        let code = UInt16(keyCode)
        if let name = functionKeys[code] { return name }
        if let name = specialKeys[code] { return name }
        if let name = printableKeys[code] { return name }
        return "#\(code)"
    }

    private static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    private static let specialKeys: [UInt16: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    /// ANSI layout — same as the system shortcut list, regardless of the current input language.
    private static let printableKeys: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 42: "\\", 43: ",", 47: ".", 44: "/", 50: "`",
        82: "Num 0", 83: "Num 1", 84: "Num 2", 85: "Num 3", 86: "Num 4", 87: "Num 5",
        88: "Num 6", 89: "Num 7", 91: "Num 8", 92: "Num 9",
        67: "Num *", 69: "Num +", 75: "Num /", 78: "Num -", 81: "Num =", 65: "Num .",
    ]
}
