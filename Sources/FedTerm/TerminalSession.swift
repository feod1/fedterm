import AppKit
import SwiftUI
import SwiftTerm

/// Terminal subclass: theme, Cmd+click on URLs and paths (like Terminal.app).
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

    /// Theme and font from settings; the background is semi-transparent — with the
    /// blur behind the panel this gives a "glassy" terminal.
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

    /// Click/drag on the terminal means text selection, not window dragging.
    /// The window is dragged by the tab bar, top, and edges, but not by the terminal area.
    override var mouseDownCanMoveWindow: Bool { false }

    /// SwiftTerm reserves a strip on the right for the scrollbar (~15px) even in overlay mode —
    /// it causes a gap on the right (noticeable in mc). Hiding the scroller zeroes the reserve,
    /// so columns take the full width. Wheel/trackpad scrolling works as before.
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

    // MARK: - Cmd+click: links and paths

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let token = tokenAt(event: event) {
            open(token: token)
            return
        }
        super.mouseDown(with: event)
    }

    /// OSC 8 — "real" hyperlinks from program output.
    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    /// Extracts the word under the mouse cursor from the terminal buffer.
    private func tokenAt(event: NSEvent) -> String? {
        let terminal = getTerminal()
        let local = convert(event.locationInWindow, from: nil)
        guard terminal.cols > 0, terminal.rows > 0, bounds.width > 0, bounds.height > 0 else { return nil }
        // SwiftTerm's cellDimension is internal — estimate from the view size
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
        // path: /abs, ~/…, ./rel — expand and reveal/open
        var path = token
        if path.hasPrefix("~") {
            path = NSString(string: path).expandingTildeInPath
        } else if path.hasPrefix("./") || !path.hasPrefix("/") {
            // relative path — resolving against the process cwd is unreliable; skip if not absolute
            guard path.hasPrefix("./") else {
                // schemeless domain: something like example.com/…
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

/// Controller for a single terminal session: owns the NSView, launches zsh,
/// reports title/directory changes and process termination upward.
final class TerminalSessionController: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    let sessionID = UUID().uuidString
    let view: FedTermView

    @Published var title: String = "zsh"
    @Published var currentDirectory: String?
    @Published var terminated = false

    /// If the tab was opened as an ssh connection — its target (for restore and title).
    var sshTarget: SSHTarget?

    /// If the tab was opened as a Claude Code session — its record and launch time (to capture the session id).
    var claudeRecordID: UUID?
    var claudeLaunchedAt: Date?
    /// A historical Claude session opened directly (without a named record).
    var claudeSessionID: String?
    /// Directory the shell started in (for restore if no OSC7 arrived).
    let startDirectory: String

    /// PID of this tab's shell — used to find a Claude instance running inside it.
    var shellPID: pid_t { view.process.shellPid }

    var onTitleChange: (() -> Void)?
    /// Called when the shell process exits — the tab closes.
    var onTerminated: (() -> Void)?
    /// Tab created by autorun of a favorite command — not saved to state
    /// (autorun will recreate it on the next launch).
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
            // let the shell start up, then "type" the command — so the preexec hook records it
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

/// SwiftUI bridge: displays the controller's already existing NSView.
struct TerminalHostView: NSViewRepresentable {
    let controller: TerminalSessionController

    func makeNSView(context: Context) -> FedTermView { controller.view }
    func updateNSView(_ nsView: FedTermView, context: Context) {}
}
