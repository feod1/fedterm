import AppKit
import Combine

/// Appearance settings: terminal theme, font, size. Stored in UserDefaults,
/// changes apply to open terminals instantly (via a notification).
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    static let appearanceChanged = Notification.Name("FedTermAppearanceChanged")
    static let hotKeyChanged = Notification.Name("FedTermHotKeyChanged")

    @Published var themeID: String {
        didSet { persistAndNotify() }
    }
    @Published var fontName: String {
        didSet { persistAndNotify() }
    }
    @Published var fontSize: Double {
        didSet { persistAndNotify() }
    }
    /// Dimming of the window's glass part (0 — pure glass, 0.95 — almost opaque).
    /// Helps on light wallpapers where the blur looks washed out.
    @Published var windowDim: Double {
        didSet { persistAndNotify() }
    }

    /// Thin strokes (like in iTerm): disables macOS font smoothing,
    /// which makes text look bolder. Takes effect after an app restart.
    @Published var thinStrokes: Bool {
        didSet {
            if thinStrokes {
                UserDefaults.standard.set(0, forKey: "AppleFontSmoothing")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleFontSmoothing")
            }
            persistAndNotify()
        }
    }
    /// Terminal font weight: regular / medium / semibold / bold.
    @Published var fontWeight: String {
        didSet { persistAndNotify() }
    }

    /// Interface language: "auto" follows the system, "ru"/"en" force one.
    /// L reads the value once at launch, so a change needs an app restart.
    @Published var appLanguage: String {
        didSet { UserDefaults.standard.set(appLanguage, forKey: "appLanguage") }
    }

    /// Global hotkey to show the window: key code and Carbon modifiers.
    /// HotkeyManager registers the shortcut itself — this is storage only.
    @Published private(set) var hotKeyCode: UInt32
    @Published private(set) var hotKeyModifiers: UInt32

    var hotKeyDisplay: String {
        HotkeyFormatter.display(keyCode: hotKeyCode, modifiers: hotKeyModifiers)
    }

    var hotKeyIsDefault: Bool {
        hotKeyCode == HotkeyManager.defaultKeyCode && hotKeyModifiers == HotkeyManager.defaultModifiers
    }

    /// Tries to claim the shortcut. false — the system refused (taken by another app),
    /// in which case the settings stay unchanged.
    func setHotKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard HotkeyManager.shared.register(keyCode: keyCode, modifiers: modifiers) else { return false }
        hotKeyCode = keyCode
        hotKeyModifiers = modifiers
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: "hotKeyCode")
        defaults.set(Int(modifiers), forKey: "hotKeyModifiers")
        NotificationCenter.default.post(name: Self.hotKeyChanged, object: nil)
        return true
    }

    @discardableResult
    func resetHotKey() -> Bool {
        setHotKey(keyCode: HotkeyManager.defaultKeyCode, modifiers: HotkeyManager.defaultModifiers)
    }

    var theme: TerminalTheme { TerminalTheme.preset(id: themeID) }

    var weightValue: NSFont.Weight {
        switch fontWeight {
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        default: return .regular
        }
    }

    var terminalFont: NSFont {
        if fontName == "system" {
            return .monospacedSystemFont(ofSize: fontSize, weight: weightValue)
        }
        var font = NSFont(name: fontName, size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: weightValue)
        // for third-party fonts, get "semibold/bold" via the bold trait
        if fontWeight == "semibold" || fontWeight == "bold" {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        return font
    }

    /// Monospaced fonts to choose from: the system one + installed ones from a known list.
    var availableFonts: [(id: String, title: String)] {
        var result: [(String, String)] = [("system", L.systemFont)]
        let candidates = [
            "Menlo", "Monaco", "JetBrainsMono-Regular", "FiraCode-Regular",
            "Hack-Regular", "CascadiaCode", "SourceCodePro-Regular", "IBMPlexMono",
            "CourierNewPSMT",
        ]
        for name in candidates where NSFont(name: name, size: 12) != nil {
            let title = NSFont(name: name, size: 12)?.familyName ?? name
            result.append((name, title))
        }
        return result
    }

    private init() {
        let defaults = UserDefaults.standard
        themeID = defaults.string(forKey: "themeID") ?? "onedark"
        fontName = defaults.string(forKey: "fontName") ?? "system"
        let size = defaults.double(forKey: "fontSize")
        fontSize = size >= 9 && size <= 28 ? size : 13
        windowDim = defaults.object(forKey: "windowDim") as? Double ?? 0.25
        fontWeight = defaults.string(forKey: "fontWeight") ?? "regular"
        appLanguage = defaults.string(forKey: "appLanguage") ?? "auto"
        thinStrokes = defaults.object(forKey: "AppleFontSmoothing") != nil
        let savedCode = defaults.object(forKey: "hotKeyCode") as? Int
        let savedModifiers = defaults.object(forKey: "hotKeyModifiers") as? Int
        hotKeyCode = savedCode.map(UInt32.init) ?? HotkeyManager.defaultKeyCode
        hotKeyModifiers = savedModifiers.map(UInt32.init) ?? HotkeyManager.defaultModifiers
    }

    func increaseFont() { fontSize = min(28, fontSize + 1) }
    func decreaseFont() { fontSize = max(9, fontSize - 1) }
    func resetFont() { fontSize = 13 }

    private func persistAndNotify() {
        let defaults = UserDefaults.standard
        defaults.set(themeID, forKey: "themeID")
        defaults.set(fontName, forKey: "fontName")
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(windowDim, forKey: "windowDim")
        defaults.set(fontWeight, forKey: "fontWeight")
        NotificationCenter.default.post(name: Self.appearanceChanged, object: nil)
    }
}
