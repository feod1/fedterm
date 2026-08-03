import Foundation
import Combine
import AppKit

/// A single tab: either "home" (spotlight with quick actions) or a terminal.
final class Tab: ObservableObject, Identifiable {
    enum Kind {
        case home
        case terminal(TerminalSessionController)
    }

    let id = UUID()
    @Published var kind: Kind
    /// Name set by the user (double-click on the tab).
    @Published var customTitle: String?

    init(kind: Kind) {
        self.kind = kind
    }

    var isHome: Bool {
        if case .home = kind { return true }
        return false
    }

    var terminal: TerminalSessionController? {
        if case .terminal(let controller) = kind { return controller }
        return nil
    }

    var title: String {
        if let custom = customTitle, !custom.isEmpty { return custom }
        switch kind {
        case .home: return L.newTabTitle
        case .terminal(let controller):
            if let target = controller.sshTarget { return target.label ?? target.displayTarget }
            return controller.title
        }
    }

    var systemImage: String {
        switch kind {
        case .home: return "sparkles"
        case .terminal(let controller):
            if controller.claudeRecordID != nil || controller.claudeSessionID != nil { return "sparkle" }
            return controller.sshTarget != nil ? "network" : "terminal"
        }
    }
}

/// State snapshot for restoring between launches.
private struct SavedState: Codable {
    struct SavedTab: Codable {
        var isHome: Bool
        var ssh: SSHTarget?
        var cwd: String?
        var title: String?
        var claudeID: UUID?
        var claudeSID: String?   // historical session without a named record
    }
    var tabs: [SavedTab]
    var selectedIndex: Int
    /// "Recents" order (⌘E) as indexes into tabs — UUIDs are new after a restart.
    /// Optional: state from older versions without this field reads as before.
    var mruIndexes: [Int]?
}

/// Tab management + state persistence (ssh tabs are restored with a reconnect).
final class TabsModel: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedID: UUID?

    let history: HistoryStore
    let claude: ClaudeSessionsStore
    private var cancellables: Set<AnyCancellable> = []
    private var isShuttingDown = false
    /// Tab usage order: most recent first (for the "recents" panel, ⌘E).
    private var mru: [UUID] = []
    private static let mruLimit = 100

    init(history: HistoryStore, claude: ClaudeSessionsStore) {
        self.history = history
        self.claude = claude
        restore()
        if tabs.isEmpty {
            tabs = [Tab(kind: .home)]
            selectedID = tabs[0].id
        }

        // when the history changes, update the ssh target of active terminals
        history.$records
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSSHTargets() }
            .store(in: &cancellables)

        // every tab switch moves it to the top of the "recents" list
        $selectedID
            .compactMap { $0 }
            .sink { [weak self] id in
                guard let self else { return }
                self.mru.removeAll { $0 == id }
                self.mru.insert(id, at: 0)
                if self.mru.count > Self.mruLimit {
                    self.mru.removeLast(self.mru.count - Self.mruLimit)
                }
                self.persist()
            }
            .store(in: &cancellables)
    }

    /// Tabs by recency of use (current one first); tabs that never had
    /// focus go last, in tab-bar order.
    var recentTabs: [Tab] {
        tabs.enumerated().sorted { a, b in
            let ia = mru.firstIndex(of: a.element.id) ?? Int.max
            let ib = mru.firstIndex(of: b.element.id) ?? Int.max
            return ia == ib ? a.offset < b.offset : ia < ib
        }.map(\.element)
    }

    var selectedTab: Tab? {
        tabs.first { $0.id == selectedID }
    }

    // MARK: - Tab operations

    func newTab(select: Bool = true) {
        let tab = Tab(kind: .home)
        tabs.append(tab)
        if select { selectedID = tab.id }
        objectWillChange.send()
        persist()
    }

    func close(_ tab: Tab) {
        guard let idx = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let terminal = tab.terminal {
            // last chance to capture the Claude session id before closing
            if let recordID = terminal.claudeRecordID, let launched = terminal.claudeLaunchedAt {
                claude.captureNow(recordID: recordID, launchedAt: launched, shellPID: terminal.shellPID)
            }
            history.appendEvent("end", sid: terminal.sessionID)
            terminal.terminate()
        }
        tabs.remove(at: idx)
        mru.removeAll { $0 == tab.id }
        if tabs.isEmpty {
            let home = Tab(kind: .home)
            tabs = [home]
            selectedID = home.id
        } else if selectedID == tab.id {
            selectedID = tabs[min(idx, tabs.count - 1)].id
        }
        persist()
        // safety net: the selection gesture could fire after closing and leave
        // the selection on a removed tab — put it back on a live one
        DispatchQueue.main.async { [weak self] in
            guard let self, self.selectedTab == nil else { return }
            self.selectedID = self.tabs.last?.id
        }
    }

    func closeSelected() {
        if let tab = selectedTab { close(tab) }
    }

    func select(index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectedID = tabs[index].id
    }

    /// Moves tab id to the position of tab targetID (for drag&drop in the tab bar).
    func move(id: UUID, to targetID: UUID) {
        guard let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
        persist()
    }

    func selectNext(delta: Int) {
        guard let current = tabs.firstIndex(where: { $0.id == selectedID }), !tabs.isEmpty else { return }
        let next = (current + delta + tabs.count) % tabs.count
        selectedID = tabs[next].id
    }

    /// Turns a tab into a terminal (or creates a new one) and runs the command.
    /// This is exactly how "the spotlight window turns into a terminal".
    @discardableResult
    func openTerminal(in tab: Tab? = nil, command: String? = nil, ssh: SSHTarget? = nil, cwd: String? = nil) -> Tab {
        let autorun = ssh?.sshCommand ?? command
        let controller = TerminalSessionController(initialDirectory: cwd, autorunCommand: autorun)
        controller.sshTarget = ssh
        controller.onTitleChange = { [weak self] in self?.objectWillChange.send() }
        history.appendEvent("start", sid: controller.sessionID)

        let target: Tab
        if let tab, tab.isHome {
            tab.kind = .terminal(controller)
            target = tab
        } else {
            target = Tab(kind: .terminal(controller))
            tabs.append(target)
        }
        // the process died (exit, ssh drop) — the tab closes itself
        controller.onTerminated = { [weak self, weak target] in
            guard let self, let target, !self.isShuttingDown else { return }
            self.close(target)
        }
        selectedID = target.id
        objectWillChange.send()
        persist()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { controller.focus() }
        return target
    }

    /// Opens (or resumes) a Claude Code session in its folder.
    @discardableResult
    func openClaude(record: ClaudeSessionRecord, in tab: Tab? = nil) -> Tab {
        let target = openTerminal(in: tab, command: claude.launchCommand(for: record), cwd: record.path)
        target.customTitle = record.name
        if let terminal = target.terminal {
            terminal.claudeRecordID = record.id
            terminal.claudeLaunchedAt = Date()
        }
        claude.markUsed(record.id)
        claude.scheduleCapture(for: record.id, launchedAt: Date(), shellPID: target.terminal?.shellPID)
        persist()
        return target
    }

    /// Opens a historical Claude session from disk (without a saved record).
    @discardableResult
    func openClaudeSession(_ session: DiscoveredSession, in tab: Tab? = nil) -> Tab {
        let target = openTerminal(in: tab, command: "claude --resume \(session.id)", cwd: session.path)
        target.customTitle = session.title
        target.terminal?.claudeSessionID = session.id
        persist()
        return target
    }

    /// If the session's last command is ssh, consider the tab "in ssh" (for the title and restore).
    private func refreshSSHTargets() {
        var changed = false
        for tab in tabs {
            guard let terminal = tab.terminal else { continue }
            if let last = history.lastCommand(sid: terminal.sessionID),
               let cmd = last.cmd {
                let parsed = SSHTarget.parse(from: cmd)
                if parsed?.displayTarget != terminal.sshTarget?.displayTarget {
                    terminal.sshTarget = parsed
                    changed = true
                }
            }
        }
        if changed { objectWillChange.send() }
        persist()
    }

    // MARK: - State between launches

    func persist() {
        guard !isShuttingDown || !tabs.isEmpty else { return }
        // don't persist autorun tabs — autorun will recreate them on the next start
        let persistable = tabs.filter { $0.terminal?.isAutorun != true }
        guard !persistable.isEmpty else { return }
        let selIdx = persistable.firstIndex(where: { $0.id == selectedID }) ?? 0
        let saved = SavedState(
            tabs: persistable.map { tab in
                SavedState.SavedTab(
                    isHome: tab.isHome,
                    ssh: tab.terminal?.sshTarget,
                    cwd: tab.terminal?.currentDirectory ?? tab.terminal?.startDirectory,
                    title: tab.customTitle,
                    claudeID: tab.terminal?.claudeRecordID,
                    claudeSID: tab.terminal?.claudeSessionID
                )
            },
            selectedIndex: selIdx,
            mruIndexes: mru.prefix(Self.mruLimit).compactMap { id in
                persistable.firstIndex { $0.id == id }
            }
        )
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: AppPaths.stateFile, options: .atomic)
        }
    }

    /// Autorun of favorite commands marked with the "pin rivet" on app start.
    func launchAutoruns(favorites: [FavoriteCommand]) {
        let previousSelection = selectedID
        for fav in favorites where fav.autorun {
            let tab = openTerminal(command: fav.command, cwd: fav.cwd)
            tab.terminal?.isAutorun = true
        }
        if let previousSelection { selectedID = previousSelection }
        persist()
    }

    private func restore() {
        guard let data = try? Data(contentsOf: AppPaths.stateFile),
              let saved = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        for savedTab in saved.tabs {
            if savedTab.isHome {
                let tab = Tab(kind: .home)
                tab.customTitle = savedTab.title
                tabs.append(tab)
            } else {
                // a Claude tab resumes its session, an ssh tab reconnects, a regular one is just a shell
                let claudeRecord = savedTab.claudeID.flatMap { claude.record(id: $0) }
                let autorun = claudeRecord.map { claude.launchCommand(for: $0) }
                    ?? savedTab.claudeSID.map { "claude --resume \($0)" }
                    ?? savedTab.ssh?.sshCommand
                let controller = TerminalSessionController(
                    initialDirectory: claudeRecord?.path ?? savedTab.cwd,
                    autorunCommand: autorun
                )
                controller.sshTarget = savedTab.ssh
                controller.claudeSessionID = savedTab.claudeSID
                if let claudeRecord {
                    controller.claudeRecordID = claudeRecord.id
                    controller.claudeLaunchedAt = Date()
                    claude.markUsed(claudeRecord.id)
                    claude.scheduleCapture(for: claudeRecord.id, launchedAt: Date(), shellPID: controller.shellPID)
                }
                controller.onTitleChange = { [weak self] in self?.objectWillChange.send() }
                history.appendEvent("start", sid: controller.sessionID)
                let tab = Tab(kind: .terminal(controller))
                tab.customTitle = savedTab.title
                controller.onTerminated = { [weak self, weak tab] in
                    guard let self, let tab, !self.isShuttingDown else { return }
                    self.close(tab)
                }
                tabs.append(tab)
            }
        }
        if !tabs.isEmpty {
            // first the "recents" order, then the selection — the sink on $selectedID
            // will move the active tab to the top of the list
            mru = (saved.mruIndexes ?? []).compactMap { idx in
                tabs.indices.contains(idx) ? tabs[idx].id : nil
            }
            let idx = min(max(0, saved.selectedIndex), tabs.count - 1)
            selectedID = tabs[idx].id
        }
    }

    func shutdown() {
        isShuttingDown = true
        persist()
        for tab in tabs {
            if let terminal = tab.terminal {
                if let recordID = terminal.claudeRecordID, let launched = terminal.claudeLaunchedAt {
                    claude.captureNow(recordID: recordID, launchedAt: launched, shellPID: terminal.shellPID)
                }
                history.appendEvent("end", sid: terminal.sessionID)
                terminal.terminate()
            }
        }
    }
}
