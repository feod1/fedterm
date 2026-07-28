import Foundation
import Combine
import AppKit

/// Одна вкладка: либо «домашняя» (спотлайт с быстрыми действиями), либо терминал.
final class Tab: ObservableObject, Identifiable {
    enum Kind {
        case home
        case terminal(TerminalSessionController)
    }

    let id = UUID()
    @Published var kind: Kind
    /// Имя, заданное пользователем (двойной клик по вкладке).
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

/// Снимок состояния для восстановления между запусками.
private struct SavedState: Codable {
    struct SavedTab: Codable {
        var isHome: Bool
        var ssh: SSHTarget?
        var cwd: String?
        var title: String?
        var claudeID: UUID?
        var claudeSID: String?   // историческая сессия без именованной записи
    }
    var tabs: [SavedTab]
    var selectedIndex: Int
}

/// Управление вкладками + сохранение состояния (ssh-табы восстанавливаются с реконнектом).
final class TabsModel: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedID: UUID?

    let history: HistoryStore
    let claude: ClaudeSessionsStore
    private var cancellables: Set<AnyCancellable> = []
    private var isShuttingDown = false

    init(history: HistoryStore, claude: ClaudeSessionsStore) {
        self.history = history
        self.claude = claude
        restore()
        if tabs.isEmpty {
            tabs = [Tab(kind: .home)]
            selectedID = tabs[0].id
        }

        // при изменении истории обновляем ssh-цель активных терминалов
        history.$records
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSSHTargets() }
            .store(in: &cancellables)
    }

    var selectedTab: Tab? {
        tabs.first { $0.id == selectedID }
    }

    // MARK: - Операции с вкладками

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
            // последний шанс поймать session id клода перед закрытием
            if let recordID = terminal.claudeRecordID, let launched = terminal.claudeLaunchedAt {
                claude.captureNow(recordID: recordID, launchedAt: launched, shellPID: terminal.shellPID)
            }
            history.appendEvent("end", sid: terminal.sessionID)
            terminal.terminate()
        }
        tabs.remove(at: idx)
        if tabs.isEmpty {
            let home = Tab(kind: .home)
            tabs = [home]
            selectedID = home.id
        } else if selectedID == tab.id {
            selectedID = tabs[min(idx, tabs.count - 1)].id
        }
        persist()
        // страховка: жест выбора мог выстрелить после закрытия и повесить
        // выделение на удалённую вкладку — возвращаем на живую
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

    /// Перемещает вкладку id на позицию вкладки targetID (для drag&drop в таб-баре).
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

    /// Превращает вкладку в терминал (или создаёт новую) и исполняет команду.
    /// Именно так «окошко-спотлайт превращается в терминал».
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
        // процесс умер (exit, разрыв ssh) — вкладка закрывается сама
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

    /// Открывает (или резюмит) сессию Claude Code в её папке.
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

    /// Открывает историческую сессию клода с диска (без сохранённой записи).
    @discardableResult
    func openClaudeSession(_ session: DiscoveredSession, in tab: Tab? = nil) -> Tab {
        let target = openTerminal(in: tab, command: "claude --resume \(session.id)", cwd: session.path)
        target.customTitle = session.title
        target.terminal?.claudeSessionID = session.id
        persist()
        return target
    }

    /// Если последняя команда сессии — ssh, считаем, что таб «в ssh» (для заголовка и восстановления).
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

    // MARK: - Состояние между запусками

    func persist() {
        guard !isShuttingDown || !tabs.isEmpty else { return }
        // автозапускаемые вкладки не сохраняем — их создаст автозапуск при следующем старте
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
            selectedIndex: selIdx
        )
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: AppPaths.stateFile, options: .atomic)
        }
    }

    /// Автозапуск избранных команд с «заклёпкой» при старте аппки.
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
                // клод-таб резюмит свою сессию, ssh-таб реконнектится, обычный — просто шелл
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
