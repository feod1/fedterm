import AppKit
import SwiftTerm

/// Акценты UI (не зависят от темы терминала).
enum Theme {
    static let accent = NSColor(hex: 0x61AFEF)
}

/// Цветовая тема терминала. Codable — кастомные темы сохраняются в json.
struct TerminalTheme: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var bg: UInt32
    var fg: UInt32
    var caret: UInt32
    var selection: UInt32
    var bgAlpha: CGFloat          // прозрачность фона поверх блюра
    var ansi: [UInt32]            // 16 цветов

    var background: NSColor { NSColor(hex: bg) }
    var foreground: NSColor { NSColor(hex: fg) }
    var caretColor: NSColor { NSColor(hex: caret) }
    var selectionColor: NSColor { NSColor(hex: selection) }

    var palette: [SwiftTerm.Color] {
        ansi.map { rgb in
            SwiftTerm.Color(
                red:   UInt16((rgb >> 16) & 0xFF) * 257,
                green: UInt16((rgb >> 8) & 0xFF) * 257,
                blue:  UInt16(rgb & 0xFF) * 257
            )
        }
    }

    static let presets: [TerminalTheme] = [
        TerminalTheme(
            // точная ANSI-палитра Terminal.app (Basic), тёмно-серый фон + светлый текст
            id: "darkgray", name: L.themeDark,
            bg: 0x2B2B2F, fg: 0xE6E6E6, caret: 0xE6E6E6, selection: 0x4A4A52, bgAlpha: 0.88,
            ansi: [
                0x000000, 0xC23621, 0x25BC24, 0xADAD27, 0x492EE1, 0xD338D3, 0x33BBC8, 0xCBCCCD,
                0x818383, 0xFC391F, 0x31E722, 0xEAEC23, 0x5833FF, 0xF935F8, 0x14F0F0, 0xE9EBEB,
            ]
        ),
        TerminalTheme(
            id: "onedark", name: "One Dark",
            bg: 0x1E2227, fg: 0xD7DAE0, caret: 0x61AFEF, selection: 0x3E4452, bgAlpha: 0.85,
            ansi: [
                0x1E2227, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF,
                0x5C6370, 0xFF7B86, 0xA9D48A, 0xF0CB8C, 0x74BBFF, 0xD48BEE, 0x67C6D3, 0xFFFFFF,
            ]
        ),
        TerminalTheme(
            id: "dracula", name: "Dracula",
            bg: 0x282A36, fg: 0xF8F8F2, caret: 0xBD93F9, selection: 0x44475A, bgAlpha: 0.86,
            ansi: [
                0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C, 0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
                0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5, 0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF,
            ]
        ),
        TerminalTheme(
            id: "nord", name: "Nord",
            bg: 0x2E3440, fg: 0xD8DEE9, caret: 0x88C0D0, selection: 0x434C5E, bgAlpha: 0.86,
            ansi: [
                0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
                0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4,
            ]
        ),
        TerminalTheme(
            id: "gruvbox", name: "Gruvbox Dark",
            bg: 0x282828, fg: 0xEBDBB2, caret: 0xFE8019, selection: 0x504945, bgAlpha: 0.87,
            ansi: [
                0x282828, 0xCC241D, 0x98971A, 0xD79921, 0x458588, 0xB16286, 0x689D6A, 0xA89984,
                0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F, 0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2,
            ]
        ),
        TerminalTheme(
            id: "solarized", name: "Solarized Dark",
            bg: 0x002B36, fg: 0x93A1A1, caret: 0x93A1A1, selection: 0x073642, bgAlpha: 0.88,
            ansi: [
                0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
                0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
            ]
        ),
        TerminalTheme(
            // точная ANSI-палитра Terminal.app (Basic), белый фон
            id: "light", name: L.themeLight,
            bg: 0xFFFFFF, fg: 0x1A1A1A, caret: 0x1A1A1A, selection: 0xB3D7FF, bgAlpha: 0.96,
            ansi: [
                0x000000, 0xC23621, 0x25BC24, 0xADAD27, 0x492EE1, 0xD338D3, 0x33BBC8, 0xCBCCCD,
                0x818383, 0xFC391F, 0x31E722, 0xEAEC23, 0x5833FF, 0xF935F8, 0x14F0F0, 0xE9EBEB,
            ]
        ),
        TerminalTheme(
            // точная ANSI-палитра Terminal.app (Basic), серый фон
            id: "lightgray", name: L.themeLightGray,
            bg: 0xE9E9EC, fg: 0x232323, caret: 0x333333, selection: 0xB8D4F5, bgAlpha: 0.97,
            ansi: [
                0x000000, 0xC23621, 0x25BC24, 0xADAD27, 0x492EE1, 0xD338D3, 0x33BBC8, 0xCBCCCD,
                0x818383, 0xFC391F, 0x31E722, 0xEAEC23, 0x5833FF, 0xF935F8, 0x14F0F0, 0xE9EBEB,
            ]
        ),
        TerminalTheme(
            id: "tokyonight", name: "Tokyo Night",
            bg: 0x1A1B26, fg: 0xC0CAF5, caret: 0x7AA2F7, selection: 0x283457, bgAlpha: 0.86,
            ansi: [
                0x15161E, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xA9B1D6,
                0x414868, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xC0CAF5,
            ]
        ),
        TerminalTheme(
            id: "catppuccin", name: "Catppuccin Mocha",
            bg: 0x1E1E2E, fg: 0xCDD6F4, caret: 0xF5E0DC, selection: 0x585B70, bgAlpha: 0.86,
            ansi: [
                0x45475A, 0xF38BA8, 0xA6E3A1, 0xF9E2AF, 0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xBAC2DE,
                0x585B70, 0xF38BA8, 0xA6E3A1, 0xF9E2AF, 0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xA6ADC8,
            ]
        ),
        TerminalTheme(
            id: "monokai", name: "Monokai",
            bg: 0x272822, fg: 0xF8F8F2, caret: 0xF8F8F2, selection: 0x49483E, bgAlpha: 0.87,
            ansi: [
                0x272822, 0xF92672, 0xA6E22E, 0xF4BF75, 0x66D9EF, 0xAE81FF, 0xA1EFE4, 0xF8F8F2,
                0x75715E, 0xF92672, 0xA6E22E, 0xF4BF75, 0x66D9EF, 0xAE81FF, 0xA1EFE4, 0xF9F8F5,
            ]
        ),
        TerminalTheme(
            id: "solarizedlight", name: "Solarized Light",
            bg: 0xFDF6E3, fg: 0x657B83, caret: 0x586E75, selection: 0xEEE8D5, bgAlpha: 0.96,
            ansi: [
                0xEEE8D5, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0x073642,
                0xFDF6E3, 0xCB4B16, 0x93A1A1, 0x839496, 0x657B83, 0x6C71C4, 0x586E75, 0x002B36,
            ]
        ),
        TerminalTheme(
            id: "github-light", name: "GitHub Light",
            bg: 0xF6F8FA, fg: 0x24292F, caret: 0x0969DA, selection: 0xB6D9FB, bgAlpha: 0.97,
            ansi: [
                0x24292F, 0xCF222E, 0x116329, 0x9A6700, 0x0969DA, 0x8250DF, 0x1B7C83, 0x6E7781,
                0x57606A, 0xFF4B4B, 0x2DA44E, 0xBF8700, 0x218BFF, 0xA475F9, 0x3192AA, 0x8C959F,
            ]
        ),
    ]

    /// Ищем сперва среди кастомных тем пользователя, потом среди пресетов.
    static func preset(id: String) -> TerminalTheme {
        CustomThemesStore.shared.theme(id: id)
            ?? presets.first { $0.id == id }
            ?? presets[0]
    }
}

/// Кастомные темы пользователя (редактор в настройках).
final class CustomThemesStore: ObservableObject {
    static let shared = CustomThemesStore()

    @Published private(set) var themes: [TerminalTheme] = []
    /// Тема, открытая в редакторе (nil — редактор закрыт).
    @Published var editing: TerminalTheme?

    private init() { load() }

    func theme(id: String) -> TerminalTheme? {
        themes.first { $0.id == id }
    }

    func upsert(_ theme: TerminalTheme) {
        if let idx = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[idx] = theme
        } else {
            themes.append(theme)
        }
        save()
    }

    func delete(id: String) {
        themes.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.customThemesFile),
              let decoded = try? JSONDecoder().decode([TerminalTheme].self, from: data) else { return }
        themes = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(themes) {
            try? data.write(to: AppPaths.customThemesFile, options: .atomic)
        }
        NotificationCenter.default.post(name: SettingsStore.appearanceChanged, object: nil)
    }
}

extension AppPaths {
    static var customThemesFile: URL { supportDir.appendingPathComponent("custom_themes.json") }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
