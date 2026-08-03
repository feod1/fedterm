import Foundation

/// Localization: follows the system language (Russian system → Russian, otherwise
/// English) unless the settings force "ru"/"en". Read once at launch — changing
/// the language in settings takes effect after an app restart.
enum L {
    static let ru: Bool = {
        switch UserDefaults.standard.string(forKey: "appLanguage") {
        case "ru": return true
        case "en": return false
        default: return Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") ?? false
        }
    }()

    // Home
    static var searchPlaceholder: String { ru ? "ssh, команда или поиск…" : "ssh, command or search…" }
    static var escToClear: String { ru ? "esc — очистить" : "esc to clear" }
    static var newTerminal: String { ru ? "Новый терминал" : "New Terminal" }
    static var newTerminalSub: String { ru ? "Пустая вкладка с шеллом" : "Empty shell tab" }
    static var favoritesSection: String { ru ? "Избранные команды" : "Favorite commands" }
    static var pinnedSection: String { ru ? "Закреплённые" : "Pinned" }
    static var recentSection: String { ru ? "Недавние подключения" : "Recent connections" }
    static func lastHourSection(_ n: Int) -> String { ru ? "За последний час · \(n) команд" : "Last hour · \(n) commands" }
    static var emptyTitle: String { ru ? "Пока пусто" : "Nothing here yet" }
    static var emptyHint: String {
        ru ? "Начни печатать команду или ssh user@host — Enter откроет терминал прямо здесь"
           : "Start typing a command or ssh user@host — Enter opens a terminal right here"
    }
    static var clickToInsert: String { ru ? "Клик — подставить в поле ввода" : "Click to insert into the field" }
    static var deleteFromHistory: String { ru ? "Удалить из истории навсегда" : "Delete from history forever" }
    static var delete: String { ru ? "Удалить" : "Delete" }
    static var runInNewTerminal: String { ru ? "Выполнить в новом терминале" : "Run in a new terminal" }
    static var connectSSH: String { ru ? "Подключиться по SSH" : "Connect via SSH" }
    static var pinnedSub: String { ru ? "Закреплено" : "Pinned" }
    static var recentSSHSub: String { ru ? "Недавнее подключение" : "Recent connection" }
    static var favoriteSub: String { ru ? "Избранная команда" : "Favorite command" }
    static var connectionName: String { ru ? "Имя подключения" : "Connection name" }
    static var rename: String { ru ? "Переименовать" : "Rename" }
    static var unpin: String { ru ? "Открепить" : "Unpin" }
    static var pin: String { ru ? "Закрепить" : "Pin" }
    static var unpinHelp: String { ru ? "Убрать из закреплённых" : "Remove from pinned" }
    static var pinHelp: String { ru ? "Закрепить на главной" : "Pin to home" }
    static var starHelp: String { ru ? "В избранное" : "Add to favorites" }
    static var unstarHelp: String { ru ? "Убрать из избранного" : "Remove from favorites" }
    static var autorunHelp: String { ru ? "Открывать при запуске аппки" : "Open on app launch" }
    static var autorunOffHelp: String { ru ? "Не открывать при запуске" : "Don't open on launch" }
    static func openClaudeIn(_ folder: String) -> String { ru ? "Открыть Claude Code — \(folder)" : "Open Claude Code — \(folder)" }

    // Tabs
    static var newTabTitle: String { ru ? "Новая вкладка" : "New Tab" }
    static var tabName: String { ru ? "Имя вкладки" : "Tab name" }
    static var resetName: String { ru ? "Сбросить имя" : "Reset name" }
    static var closeTab: String { ru ? "Закрыть вкладку" : "Close Tab" }
    static var newTabHelp: String { ru ? "Новая вкладка (⌘T)" : "New tab (⌘T)" }
    static var recentTabsTitle: String { ru ? "Недавние вкладки" : "Recent tabs" }
    static var recentTabsHint: String {
        ru ? "↑↓ или ⌘E — навигация · ⏎ — перейти · esc — закрыть"
           : "↑↓ or ⌘E to navigate · ⏎ to switch · esc to close"
    }
    static var recentTabHome: String { ru ? "Быстрые действия" : "Quick actions" }
    static var hotkeysTitle: String { ru ? "Горячие клавиши" : "Hotkeys" }
    static var hkTabs: String { ru ? "новая / закрыть вкладку" : "new / close tab" }
    static var hkSwitchTab: String { ru ? "переключить вкладку" : "switch tab" }
    static var hkPrevNextTab: String { ru ? "соседняя вкладка" : "previous / next tab" }
    static var hkRecentTabs: String { ru ? "недавние вкладки" : "recent tabs" }
    static var hkFontSize: String { ru ? "размер шрифта" : "font size" }
    static var hkOpenLink: String { ru ? "открыть ссылку или путь" : "open link or path" }
    static var hkInterrupt: String { ru ? "прервать программу" : "interrupt the program" }
    static var hkClick: String { ru ? "клик" : "click" }
    static var languageTitle: String { ru ? "ЯЗЫК ИНТЕРФЕЙСА" : "INTERFACE LANGUAGE" }
    static var languageAuto: String { ru ? "Как в системе" : "System default" }
    static var pinWindowOn: String { ru ? "Окно не будет скрываться" : "Window will stay visible" }
    static var pinWindowOff: String { ru ? "Закрепить окно (не скрывать при потере фокуса)" : "Pin window (don't hide on focus loss)" }

    // Claude
    static var newClaudeSession: String { ru ? "Новая сессия Claude" : "New Claude Session" }
    static var sessionName: String { ru ? "Название сессии" : "Session name" }
    static var cancel: String { ru ? "Отмена" : "Cancel" }
    static var openClaude: String { ru ? "Открыть Claude" : "Open Claude" }
    static var claudeSessionsHelp: String { ru ? "Сессии Claude Code" : "Claude Code sessions" }
    static var savedSegment: String { ru ? "Сохранённые" : "Saved" }
    static var historySegment: String { ru ? "Вся история" : "All history" }
    static var searchSessions: String { ru ? "Поиск по названию или папке…" : "Search by name or folder…" }
    static var noSavedSessions: String { ru ? "Пока нет сохранённых сессий" : "No saved sessions yet" }
    static var noSavedHint: String {
        ru ? "Перетащи папку проекта из WebStorm в окно — откроется\nClaude Code. Или сохрани звёздочкой любую из «Вся история»"
           : "Drag a project folder into the window to open\nClaude Code. Or star any session from All history"
    }
    static var last24h: String { ru ? "Последние 24 часа" : "Last 24 hours" }
    static var last7d: String { ru ? "За 7 дней" : "Last 7 days" }
    static var lastMonth: String { ru ? "За месяц" : "Last month" }
    static var earlier: String { ru ? "Ранее" : "Earlier" }
    static func showMore(_ n: Int) -> String { ru ? "Показать ещё (\(n))" : "Show more (\(n))" }
    static func nothingFound(_ q: String) -> String { ru ? "Ничего не нашлось по «\(q)»" : "Nothing found for “\(q)”" }
    static var resumes: String { ru ? "· резюмится" : "· resumable" }
    static var alreadySaved: String { ru ? "Уже в сохранённых" : "Already saved" }
    static var saveForever: String { ru ? "Сохранить навсегда" : "Save forever" }
    static var deleteFromList: String { ru ? "Удалить из списка (сессия Claude на диске останется)" : "Remove from list (Claude session stays on disk)" }
    static var dropHint: String { ru ? "Отпусти — откроем Claude Code в этой папке" : "Drop to open Claude Code in this folder" }
    static var newSession: String { ru ? "Новая сессия" : "New session" }
    static var choose: String { ru ? "Выбрать" : "Choose" }
    static var newSessionHelp: String { ru ? "Создать новую сессию Claude в выбранной папке" : "Create a new Claude session in a chosen folder" }

    // Settings
    static var settings: String { ru ? "Настройки" : "Settings" }
    static var colorTheme: String { ru ? "ЦВЕТОВАЯ ТЕМА" : "COLOR THEME" }
    static var font: String { ru ? "ШРИФТ" : "FONT" }
    static func fontSize(_ n: Int) -> String { ru ? "Размер: \(n)" : "Size: \(n)" }
    static var reset: String { ru ? "Сброс" : "Reset" }
    static var fontHint: String { ru ? "⌘ + / ⌘ − — размер шрифта, ⌘ 0 — сброс" : "⌘ + / ⌘ − font size, ⌘ 0 reset" }
    static var globalHotkey: String { ru ? "ГЛОБАЛЬНЫЙ ХОТКЕЙ" : "GLOBAL HOTKEY" }
    static var hotkeyHint: String {
        ru ? "Показывает и прячет окно. Кликни, чтобы назначить своё сочетание."
           : "Shows and hides the window. Click to set your own shortcut."
    }
    static var hotkeyPressPrompt: String { ru ? "Нажми сочетание" : "Press a shortcut" }
    static var hotkeyEscHint: String {
        ru ? "Нажми любое сочетание · esc — отмена · ⌫ — вернуть ⌥Space"
           : "Press any shortcut · esc to cancel · ⌫ for the default ⌥Space"
    }
    static var hotkeyNeedsModifier: String {
        ru ? "Одной клавиши мало — добавь ⌘, ⌥, ⌃ или ⇧ (F-клавиши можно без них)"
           : "A single key isn't enough — add ⌘, ⌥, ⌃ or ⇧ (F-keys work on their own)"
    }
    static var hotkeyTaken: String {
        ru ? "Это сочетание уже занято другой программой" : "That shortcut is already taken by another app"
    }
    static func hotkeySaved(_ combo: String) -> String {
        ru ? "Готово: теперь окно открывается по \(combo)" : "Done — the window now opens with \(combo)"
    }
    static var hotkeyReset: String { ru ? "Вернули ⌥Space" : "Back to ⌥Space" }
    static var hotkeyResetHelp: String { ru ? "Вернуть ⌥Space" : "Reset to ⌥Space" }
    static var hotkeyRecordHelp: String { ru ? "Кликни и нажми новое сочетание" : "Click, then press a new shortcut" }
    static var windowOpacity: String { ru ? "ПРОЗРАЧНОСТЬ ОКНА" : "WINDOW OPACITY" }
    static var glassy: String { ru ? "стекло" : "glass" }
    static var solid: String { ru ? "плотно" : "solid" }
    static var systemFont: String { ru ? "SF Mono (системный)" : "SF Mono (system)" }
    static var thinStrokes: String { ru ? "Тонкие штрихи (чётче, как в iTerm)" : "Thin strokes (crisper, like iTerm)" }
    static var needsRestart: String { ru ? "применится после перезапуска аппки" : "applies after app restart" }
    static var fontWeightLabel: String { ru ? "Толщина" : "Weight" }
    static var weightRegular: String { ru ? "Обычный" : "Regular" }
    static var weightMedium: String { ru ? "Средний" : "Medium" }
    static var weightSemibold: String { ru ? "Полужирный" : "Semibold" }
    static var weightBold: String { ru ? "Жирный" : "Bold" }
    static var themeNewFromCurrent: String { ru ? "Новая тема из текущей" : "New theme from current" }
    static var themeEdit: String { ru ? "Редактировать" : "Edit" }
    static var themeDelete: String { ru ? "Удалить" : "Delete" }
    static var themeEditorTitle: String { ru ? "Редактор темы" : "Theme Editor" }
    static var themeName: String { ru ? "Название темы" : "Theme name" }
    static var baseColors: String { ru ? "ОСНОВНЫЕ" : "BASE" }
    static var ansiColorsLabel: String { ru ? "ANSI-ЦВЕТА (обычные / яркие)" : "ANSI COLORS (normal / bright)" }
    static var colorBg: String { ru ? "Фон" : "Background" }
    static var colorFg: String { ru ? "Текст" : "Text" }
    static var colorCaret: String { ru ? "Курсор" : "Caret" }
    static var colorSelection: String { ru ? "Выделение" : "Selection" }
    static var terminalAlpha: String { ru ? "Непрозрачность фона терминала" : "Terminal background opacity" }
    static var save: String { ru ? "Сохранить" : "Save" }
    static var copySuffix: String { ru ? "копия" : "copy" }
    static var themeLight: String { ru ? "Светлая" : "Light" }
    static var themeDark: String { ru ? "Тёмная" : "Dark" }
    static var themeLightGray: String { ru ? "Светло-серая" : "Light Gray" }

    // History buckets
    static var bucketHour: String { ru ? "За последний час" : "Last hour" }
    static var bucket6h: String { ru ? "За последние 6 часов" : "Last 6 hours" }
    static var bucketDay: String { ru ? "За сутки" : "Last 24 hours" }
    static var bucketYesterday: String { ru ? "Вчера" : "Yesterday" }
    static var bucketWeek: String { ru ? "За неделю" : "Last week" }
    static var bucketEarlier: String { ru ? "Ранее" : "Earlier" }

    // Automations
    static var automations: String { ru ? "АВТОМАТИЗАЦИИ (⌃1–⌃9)" : "AUTOMATIONS (⌃1–⌃9)" }
    static var automationPlaceholder: String { ru ? "bash-команда…" : "bash command…" }
    static var add: String { ru ? "Добавить" : "Add" }
    static var noFreeKeys: String { ru ? "Все ⌃1–⌃9 заняты" : "All ⌃1–⌃9 are taken" }
    static var automationHint: String { ru ? "Работают только при открытом окне, в систему не уходят" : "Active only while the window is open, not passed to the system" }
    static var workingDir: String { ru ? "Папка запуска" : "Working directory" }
    static var addAutomation: String { ru ? "Добавить автоматизацию" : "Add automation" }
    static var scriptFromFile: String { ru ? "Скрипт из файла…" : "Script from file…" }
    static var hotkeyLabel: String { ru ? "Хоткей" : "Hotkey" }
    static func historySection(_ n: Int) -> String { ru ? "История команд · \(n)" : "Command history · \(n)" }

    // App menu / quit
    static var hideApp: String { ru ? "Скрыть FedTerm" : "Hide FedTerm" }
    static var quit: String { ru ? "Выйти" : "Quit" }
    static var edit: String { ru ? "Правка" : "Edit" }
    static var undo: String { ru ? "Отменить" : "Undo" }
    static var cut: String { ru ? "Вырезать" : "Cut" }
    static var copy: String { ru ? "Скопировать" : "Copy" }
    static var paste: String { ru ? "Вставить" : "Paste" }
    static var selectAll: String { ru ? "Выбрать всё" : "Select All" }
    static var toggleWindow: String { ru ? "Показать/скрыть" : "Show/Hide" }
    static var quitConfirmTitle: String { ru ? "Закрыть FedTerm?" : "Quit FedTerm?" }
    static func quitConfirmText(_ n: Int) -> String {
        ru ? "Открыто вкладок с процессами: \(n). Сессии сохранятся и восстановятся при следующем запуске."
           : "\(n) tabs with running processes are open. Sessions will be saved and restored on next launch."
    }
    static var quitButton: String { ru ? "Выйти" : "Quit" }
}
