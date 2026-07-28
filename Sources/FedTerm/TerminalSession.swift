import AppKit
import SwiftUI
import SwiftTerm

/// Сабкласс терминала: тема, Cmd+click по URL и путям (как в Terminal.app).
final class FedTermView: LocalProcessTerminalView {
    private var appearanceObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyAppearance()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: SettingsStore.appearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer = appearanceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Тема и шрифт из настроек; фон полупрозрачный — под панелью блюр,
    /// получается «стеклянный» терминал.
    private func applyAppearance() {
        let settings = SettingsStore.shared
        let theme = settings.theme
        font = settings.terminalFont
        installColors(theme.palette)
        nativeForegroundColor = theme.foreground
        nativeBackgroundColor = theme.background.withAlphaComponent(theme.bgAlpha)
        caretColor = theme.caretColor
        selectedTextBackgroundColor = theme.selectionColor
        layer?.backgroundColor = .clear
        needsDisplay = true
    }

    /// Клик/драг по терминалу — это выделение текста, а не перенос окна.
    /// Окно таскается за таб-бар, верх и края, но не за область терминала.
    override var mouseDownCanMoveWindow: Bool { false }

    /// SwiftTerm резервирует справа полосу под скроллбар (~15px) даже в overlay-режиме —
    /// из-за неё щель справа (заметно в mc). Прячем скроллер: резерв обнуляется,
    /// колонки занимают всю ширину. Скролл колёсиком/трекпадом работает как раньше.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideScroller()
    }

    private func hideScroller() {
        for sub in subviews where sub is NSScroller {
            sub.isHidden = true
        }
        needsLayout = true
    }

    // MARK: - Cmd+click: ссылки и пути

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let token = tokenAt(event: event) {
            open(token: token)
            return
        }
        super.mouseDown(with: event)
    }

    /// OSC 8 — «настоящие» гиперссылки из вывода программ.
    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    /// Достаёт слово под курсором мыши из буфера терминала.
    private func tokenAt(event: NSEvent) -> String? {
        let terminal = getTerminal()
        let local = convert(event.locationInWindow, from: nil)
        guard terminal.cols > 0, terminal.rows > 0, bounds.width > 0, bounds.height > 0 else { return nil }
        // cellDimension у SwiftTerm внутренний — оцениваем по размеру вью
        let cellWidth = bounds.width / CGFloat(terminal.cols)
        let cellHeight = bounds.height / CGFloat(terminal.rows)
        let col = max(0, min(terminal.cols - 1, Int(local.x / cellWidth)))
        let row = max(0, min(terminal.rows - 1, Int((bounds.height - local.y) / cellHeight)))
        guard let line = terminal.getLine(row: row) else { return nil }
        let text = line.translateToString(trimRight: false)
        let chars = Array(text)
        guard col < chars.count else { return nil }

        let delimiters: Set<Character> = [" ", "\t", "\"", "'", "(", ")", "<", ">", "`", "\u{0}"]
        var start = col, end = col
        if delimiters.contains(chars[col]) { return nil }
        while start > 0, !delimiters.contains(chars[start - 1]) { start -= 1 }
        while end < chars.count - 1, !delimiters.contains(chars[end + 1]) { end += 1 }
        var token = String(chars[start...end]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        token = token.trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    private func open(token: String) {
        // URL
        if token.hasPrefix("http://") || token.hasPrefix("https://") || token.contains("://") {
            if let url = URL(string: token) { NSWorkspace.shared.open(url); return }
        }
        // путь: /abs, ~/…, ./rel — раскрываем и показываем/открываем
        var path = token
        if path.hasPrefix("~") {
            path = NSString(string: path).expandingTildeInPath
        } else if path.hasPrefix("./") || !path.hasPrefix("/") {
            // относительный путь — пробуем от текущей директории процесса неточно; пропускаем, если не абсолютный
            guard path.hasPrefix("./") else {
                // домен без схемы: что-то похожее на example.com/…
                if token.contains(".") && !token.contains("/") || token.hasPrefix("www.") {
                    if let url = URL(string: "https://\(token)") { NSWorkspace.shared.open(url) }
                }
                return
            }
            path = String(path.dropFirst(2))
        }
        let expanded = (path as NSString).isAbsolutePath ? path : path
        if FileManager.default.fileExists(atPath: expanded) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expanded)])
        }
    }
}

/// Контроллер одной терминальной сессии: владеет NSView, запускает zsh,
/// сообщает наверх про смену заголовка/каталога/завершение процесса.
final class TerminalSessionController: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    let sessionID = UUID().uuidString
    let view: FedTermView

    @Published var title: String = "zsh"
    @Published var currentDirectory: String?
    @Published var terminated = false

    /// Если таб открыт как ssh-подключение — его цель (для восстановления и заголовка).
    var sshTarget: SSHTarget?

    /// Если таб открыт как сессия Claude Code — запись и момент запуска (для захвата session id).
    var claudeRecordID: UUID?
    var claudeLaunchedAt: Date?
    /// Историческая сессия клода, открытая напрямую (без именованной записи).
    var claudeSessionID: String?
    /// Папка, в которой стартовал шелл (для восстановления, если OSC7 не пришёл).
    let startDirectory: String

    /// PID шелла этой вкладки — по нему находим запущенный внутри клод.
    var shellPID: pid_t { view.process.shellPid }

    var onTitleChange: (() -> Void)?
    /// Вызывается при завершении процесса шелла — вкладка закрывается.
    var onTerminated: (() -> Void)?
    /// Вкладка создана автозапуском избранной команды — не сохраняется в стейт
    /// (при следующем старте автозапуск создаст её заново).
    var isAutorun = false

    init(initialDirectory: String? = nil, autorunCommand: String? = nil) {
        view = FedTermView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let cwd = initialDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        startDirectory = cwd
        super.init()
        view.processDelegate = self

        ShellIntegration.ensureInstalled()
        let env = ShellIntegration.environment(sessionID: sessionID)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(
            executable: shell,
            args: ["-l", "-i"],
            environment: env,
            currentDirectory: cwd
        )

        if let cmd = autorunCommand {
            // даём шеллу подняться и «печатаем» команду — так её запишет preexec-хук
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.view.send(txt: cmd + "\n")
            }
        }
    }

    func terminate() {
        view.terminate()
    }

    func focus() {
        view.window?.makeFirstResponder(view)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async {
            self.title = title.isEmpty ? "zsh" : title
            self.onTitleChange?()
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        DispatchQueue.main.async {
            if let dir = directory, let url = URL(string: dir), url.isFileURL {
                self.currentDirectory = url.path
            } else {
                self.currentDirectory = directory
            }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            self.terminated = true
            self.onTitleChange?()
            self.onTerminated?()
        }
    }
}

/// Мост в SwiftUI: показывает уже существующий NSView контроллера.
struct TerminalHostView: NSViewRepresentable {
    let controller: TerminalSessionController

    func makeNSView(context: Context) -> FedTermView { controller.view }
    func updateNSView(_ nsView: FedTermView, context: Context) {}
}
