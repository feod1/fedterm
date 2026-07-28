import SwiftUI
import AppKit

/// Что можно выбрать в спотлайт-списке.
enum HomeItem: Identifiable {
    case plainTerminal                    // пустой терминал с шеллом
    case runQuery(String)                 // выполнить введённый текст как команду
    case sshQuery(SSHTarget)              // введённое похоже на user@host — сразу ssh
    case claudeFolder(String)             // введён абсолютный путь к папке — открыть Claude
    case favorite(FavoriteCommand)        // избранная команда (звёздочка)
    case pinned(SSHTarget)
    case recentSSH(SSHTarget)
    case recentCommand(CommandRecord)

    var id: String {
        switch self {
        case .plainTerminal: return "term"
        case .runQuery(let q): return "run:\(q)"
        case .sshQuery(let t): return "sshq:\(t.id)"
        case .claudeFolder(let p): return "claude:\(p)"
        case .favorite(let f): return "fav:\(f.id)"
        case .pinned(let t): return "pin:\(t.id)"
        case .recentSSH(let t): return "recent:\(t.id)"
        case .recentCommand(let r): return "cmd:\(r.id)"
        }
    }
}

/// Спотлайт-домашняя: большое поле ввода, быстрые действия, история за час.
struct HomeView: View {
    let tab: Tab

    @EnvironmentObject var tabs: TabsModel
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var pins: PinsStore
    @EnvironmentObject var claude: ClaudeSessionsStore
    @EnvironmentObject var favorites: FavoritesStore

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @State private var historyVisible = 15
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        itemsList
                        if query.isEmpty { hourSummary }
                    }
                    .padding(10)
                }
                .onChange(of: selectedIndex) { idx in
                    let items = visibleItems
                    withAnimation(.easeOut(duration: 0.12)) {
                        if idx < items.count {
                            proxy.scrollTo(items[idx].id, anchor: nil)
                        } else {
                            let hist = historyItems
                            let hIdx = idx - items.count
                            if hIdx < hist.count {
                                proxy.scrollTo("hist-\(hist[hIdx].id)", anchor: nil)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            fieldFocused = true
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onReceive(PanelBridge.shared.panelShown) { _ in
            // панель показали хоткеем — сразу фокус в поле ввода
            guard tabs.selectedTab?.id == tab.id else { return }
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onChange(of: query) { _ in selectedIndex = 0 }
    }

    // MARK: - Поле ввода

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
            TextField(L.searchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .light))
                .focused($fieldFocused)
                .onSubmit { execute(at: selectedIndex) }
            if !query.isEmpty {
                Text(L.escToClear)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Список

    private var visibleItems: [HomeItem] {
        var items: [HomeItem] = []
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            // абсолютный путь к папке (из WebStorm и т.п.) → открыть Claude Code в ней
            if q.hasPrefix("/") || q.hasPrefix("~") {
                let expanded = NSString(string: q).expandingTildeInPath
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                    items.append(.claudeFolder(expanded))
                }
            }
            // «ssh user@host» парсим как есть, «user@host» — дописываем ssh
            let sshInput = (q.hasPrefix("ssh ") || q.hasPrefix("ssh://")) ? q : "ssh \(q)"
            var sshTarget: SSHTarget?
            if q.contains("@") || q.contains(".") || q.hasPrefix("ssh ") {
                sshTarget = SSHTarget.parse(from: sshInput)
            }
            if let target = sshTarget {
                items.append(.sshQuery(target))
            }
            // не дублируем: если введённое — та же ssh-команда, «Выполнить…» не нужно
            if sshTarget == nil || !q.hasPrefix("ssh") {
                items.append(.runQuery(q))
            }
            let ql = q.lowercased()
            let matchedFavs = favorites.favorites.filter {
                $0.command.lowercased().contains(ql)
                    || ($0.label?.lowercased().contains(ql) ?? false)
            }
            items += matchedFavs.map { HomeItem.favorite($0) }
            items += pins.pins
                .filter { matches($0, ql) }
                .map { HomeItem.pinned($0) }
            items += history.recentSSHTargets(limit: 20)
                .filter { target in matches(target, ql) && !pins.isPinned(target) }
                .map { HomeItem.recentSSH($0) }

            // фаззи-поиск по истории команд: подсеквенция с оценкой,
            // без дублей и без команд, уже показанных в избранном
            let favCmds = Set(matchedFavs.map(\.command))
            var seenCmds = Set<String>()
            var scored: [(CommandRecord, Int)] = []
            for rec in history.recentCommands(limit: 200) {
                guard let cmd = rec.cmd, !favCmds.contains(cmd), !seenCmds.contains(cmd),
                      cmd.lowercased() != ql,
                      let score = Self.fuzzyScore(ql, cmd.lowercased()) else { continue }
                seenCmds.insert(cmd)
                scored.append((rec, score))
            }
            items += scored.sorted { $0.1 > $1.1 }.prefix(8).map { HomeItem.recentCommand($0.0) }
        } else {
            items.append(.plainTerminal)
            items += favorites.favorites.map { HomeItem.favorite($0) }
            items += pins.pins.map { HomeItem.pinned($0) }
            items += history.recentSSHTargets(limit: 8)
                .filter { !pins.isPinned($0) }
                .map { HomeItem.recentSSH($0) }
        }
        return items
    }

    private func matches(_ target: SSHTarget, _ q: String) -> Bool {
        target.displayTarget.lowercased().contains(q) || (target.label?.lowercased().contains(q) ?? false)
    }

    /// Видимая часть истории — тоже участвует в стрелочной навигации
    /// (индексы продолжаются после visibleItems). С дедупом внутри временных групп.
    private var historyItems: [CommandRecord] {
        guard query.isEmpty else { return [] }
        return Array(dedupHistory(history.recentCommands(limit: 200)).prefix(historyVisible))
    }

    /// Фаззи-матч: буквы запроса встречаются в строке по порядку.
    /// Очки выше за префикс, компактность и раннее вхождение; nil — не совпало.
    static func fuzzyScore(_ query: String, _ text: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let q = Array(query), t = Array(text)
        var qi = 0, first = -1, last = -1
        var i = 0
        while i < t.count && qi < q.count {
            if t[i] == q[qi] {
                if first < 0 { first = i }
                last = i
                qi += 1
            }
            i += 1
        }
        guard qi == q.count else { return nil }
        var score = 100
        let gaps = last - first + 1 - q.count
        score -= min(50, gaps * 3)     // разрывы между буквами
        score -= min(30, first)        // чем раньше начало — тем лучше
        if text.hasPrefix(query) { score += 40 }
        return score
    }

    @ViewBuilder
    private var itemsList: some View {
        let items = visibleItems
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if query.isEmpty { sectionHeaderIfNeeded(items, index) }
            HomeRow(
                item: item,
                isSelected: index == selectedIndex,
                isPinned: pinTarget(of: item).map(pins.isPinned) ?? false,
                isFavorite: favoriteCommand(of: item).map(favorites.isFavorite) ?? false,
                onPin: { if let t = pinTarget(of: item) { pins.toggle(t) } },
                onRename: renameAction(for: item),
                onStar: starAction(for: item),
                onAutorun: autorunAction(for: item)
            )
            .id(item.id)
            .contentShape(Rectangle())
            .onTapGesture { execute(at: index) }
            .onHover { hovering in if hovering { selectedIndex = index } }
        }
        if items.count <= 1 && query.isEmpty && favorites.favorites.isEmpty && pins.pins.isEmpty {
            VStack(spacing: 6) {
                Text(L.emptyTitle)
                    .foregroundStyle(.secondary)
                Text(L.emptyHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    /// Заголовок секции перед первым элементом каждого типа (только при пустом поиске).
    @ViewBuilder
    private func sectionHeaderIfNeeded(_ items: [HomeItem], _ index: Int) -> some View {
        if isFirstOfKind(items, index) {
            switch items[index] {
            case .favorite: sectionHeader(L.favoritesSection)
            case .pinned: sectionHeader(L.pinnedSection)
            case .recentSSH: sectionHeader(L.recentSection)
            default: EmptyView()
            }
        }
    }

    private func isFirstOfKind(_ items: [HomeItem], _ index: Int) -> Bool {
        func kind(_ item: HomeItem) -> Int {
            switch item {
            case .favorite: return 1
            case .pinned: return 2
            case .recentSSH: return 3
            default: return 0
            }
        }
        let k = kind(items[index])
        guard k != 0 else { return false }
        return index == 0 || kind(items[index - 1]) != k
    }

    private func pinTarget(of item: HomeItem) -> SSHTarget? {
        switch item {
        case .pinned(let t), .recentSSH(let t), .sshQuery(let t): return t
        default: return nil
        }
    }

    private func favoriteCommand(of item: HomeItem) -> String? {
        switch item {
        case .favorite(let f): return f.command
        case .recentCommand(let r): return r.cmd
        case .runQuery(let q): return q
        default: return nil
        }
    }

    /// Переименование: ssh-пины и избранные команды.
    private func renameAction(for item: HomeItem) -> ((String?) -> Void)? {
        switch item {
        case .pinned(let target):
            return { label in pins.rename(target, label: label) }
        case .favorite(let fav):
            return { label in favorites.rename(fav.id, label: label) }
        default:
            return nil
        }
    }

    /// Звёздочка: добавить/убрать команду из избранного.
    private func starAction(for item: HomeItem) -> (() -> Void)? {
        switch item {
        case .favorite(let fav):
            return { favorites.remove(fav.id) }
        case .recentCommand(let rec):
            guard let cmd = rec.cmd else { return nil }
            return { favorites.toggle(command: cmd, cwd: rec.cwd) }
        case .runQuery(let q):
            return { favorites.toggle(command: q, cwd: nil) }
        default:
            return nil
        }
    }

    /// «Заклёпка»: открывать команду при запуске аппки (только для избранных).
    private func autorunAction(for item: HomeItem) -> (() -> Void)? {
        guard case .favorite(let fav) = item else { return nil }
        return { favorites.toggleAutorun(fav.id) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    // MARK: - История команд (полный список, свежие сверху, порциями)

    @ViewBuilder
    private var hourSummary: some View {
        let summary = history.summary()
        let total = dedupHistory(history.recentCommands(limit: 200)).count
        if total > 0 {
            sectionHeader(L.historySection(total))
            // чипы за последний час: ssh-хосты кликабельны, остальное — счётчики
            if !summary.isEmpty {
                FlowChips(summary: summary) { target in
                    tabs.openTerminal(in: tab, ssh: target)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }

            let hist = historyItems
            let base = visibleItems.count
            ForEach(Array(hist.enumerated()), id: \.element.id) { idx, rec in
                // заголовок временно́й группы — при смене группы
                if idx == 0 || bucketIndex(rec.ts) != bucketIndex(hist[idx - 1].ts) {
                    Text(Self.bucketLabels[bucketIndex(rec.ts)].uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
                historyRow(rec, isSelected: base + idx == selectedIndex)
                    .id("hist-\(rec.id)")
                    .onTapGesture { execute(at: base + idx) }
                    .onHover { hovering in if hovering { selectedIndex = base + idx } }
            }

            if total > historyVisible {
                Button {
                    historyVisible += 45
                } label: {
                    Text(L.showMore(total - historyVisible))
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
        }
    }

    private static let bucketLabels = [
        L.bucketHour, L.bucket6h, L.bucketDay, L.bucketYesterday, L.bucketWeek, L.bucketEarlier,
    ]

    private func bucketIndex(_ ts: Double) -> Int {
        let age = Date().timeIntervalSince1970 - ts
        switch age {
        case ..<3600: return 0
        case ..<(6 * 3600): return 1
        case ..<(24 * 3600): return 2
        case ..<(48 * 3600): return 3
        case ..<(7 * 86400): return 4
        default: return 5
        }
    }

    /// Одна и та же команда внутри временно́й группы показывается один раз (самый свежий запуск).
    private func dedupHistory(_ items: [CommandRecord]) -> [CommandRecord] {
        var seen = Set<String>()
        return items.filter { rec in
            guard let cmd = rec.cmd else { return false }
            let key = "\(bucketIndex(rec.ts))|\(cmd)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func historyRow(_ rec: CommandRecord, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: CommandKind.classify(rec.cmd ?? "").icon)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Text(rec.cmd ?? "")
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)
            Spacer()
            if let cmd = rec.cmd {
                Button {
                    favorites.toggle(command: cmd, cwd: rec.cwd)
                } label: {
                    Image(systemName: favorites.isFavorite(cmd) ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(favorites.isFavorite(cmd) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .opacity(isSelected || favorites.isFavorite(cmd ) ? 1 : 0)
                .help(favorites.isFavorite(cmd) ? L.unstarHelp : L.starHelp)
            }
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Text(rec.date, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.white.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Действия

    private func execute(at index: Int) {
        guard !PanelBridge.shared.editingText else { return }
        let items = visibleItems
        guard index >= 0, index < items.count else {
            // индексы дальше списка — это строки истории
            let hist = historyItems
            let hIdx = index - items.count
            if hIdx >= 0, hIdx < hist.count, let cmd = hist[hIdx].cmd {
                tabs.openTerminal(in: tab, command: cmd, cwd: hist[hIdx].cwd)
                return
            }
            let q = query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { tabs.openTerminal(in: tab, command: q) }
            return
        }
        switch items[index] {
        case .plainTerminal:
            tabs.openTerminal(in: tab)
        case .runQuery(let cmd):
            tabs.openTerminal(in: tab, command: cmd)
        case .sshQuery(let target), .pinned(let target), .recentSSH(let target):
            tabs.openTerminal(in: tab, ssh: target)
        case .claudeFolder(let path):
            query = ""
            claude.pendingFolder = URL(fileURLWithPath: path)
        case .favorite(let fav):
            tabs.openTerminal(in: tab, command: fav.command, cwd: fav.cwd)
        case .recentCommand(let rec):
            if let cmd = rec.cmd { tabs.openTerminal(in: tab, command: cmd, cwd: rec.cwd) }
        }
    }

    // MARK: - Клавиатура (стрелки/enter/esc как в спотлайте)

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard tabs.selectedTab?.id == tab.id, tab.isHome,
                  !PanelBridge.shared.editingText else { return event }
            switch event.keyCode {
            case 125: // down — сквозь быстрые действия и дальше по истории
                let total = visibleItems.count + historyItems.count
                selectedIndex = min(selectedIndex + 1, max(0, total - 1))
                return nil
            case 126: // up
                selectedIndex = max(0, selectedIndex - 1)
                return nil
            case 36: // return
                execute(at: selectedIndex)
                return nil
            case 53: // esc
                if !query.isEmpty {
                    query = ""
                } else {
                    PanelBridge.shared.hide()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

/// Строка результата в спотлайт-списке.
private struct HomeRow: View {
    let item: HomeItem
    let isSelected: Bool
    let isPinned: Bool
    let isFavorite: Bool
    let onPin: () -> Void
    var onRename: ((String?) -> Void)?
    var onStar: (() -> Void)?
    var onAutorun: (() -> Void)?

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    TextField(L.connectionName, text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($editFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                } else {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !editing { accessories }
            if isSelected, !editing {
                Image(systemName: "return")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.12) : .clear)
        )
        .contextMenu {
            if onRename != nil {
                Button(L.rename) { startRename() }
            }
            if showsPin {
                Button(isPinned ? L.unpin : L.pin) { onPin() }
            }
            if onStar != nil {
                Button(isFavorite ? L.unstarHelp : L.starHelp) { onStar?() }
            }
        }
    }

    @ViewBuilder
    private var accessories: some View {
        // автозапуск («заклёпка») — только у избранных
        if case .favorite(let fav) = item, let onAutorun {
            Button(action: onAutorun) {
                Image(systemName: fav.autorun ? "bolt.fill" : "bolt")
                    .font(.system(size: 11))
                    .foregroundStyle(fav.autorun ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isSelected || fav.autorun ? 1 : 0)
            .help(fav.autorun ? L.autorunOffHelp : L.autorunHelp)
        }
        if onRename != nil {
            Button { startRename() } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isSelected ? 1 : 0)
            .help(L.rename)
        }
        if let onStar {
            Button(action: onStar) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isSelected || isFavorite ? 1 : 0)
            .help(isFavorite ? L.unstarHelp : L.starHelp)
        }
        if showsPin {
            Button(action: onPin) {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(isPinned ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isSelected || isPinned ? 1 : 0)
            .help(isPinned ? L.unpinHelp : L.pinHelp)
        }
    }

    private func startRename() {
        if case .pinned(let target) = item {
            draft = target.label ?? ""
        }
        if case .favorite(let fav) = item {
            draft = fav.label ?? ""
        }
        editing = true
        PanelBridge.shared.editingText = true
        DispatchQueue.main.async { editFocused = true }
    }

    private func commitRename() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        onRename?(name.isEmpty ? nil : name)
        editing = false
        PanelBridge.shared.editingText = false
    }

    private func cancelRename() {
        editing = false
        PanelBridge.shared.editingText = false
    }

    private var showsPin: Bool {
        switch item {
        case .pinned, .recentSSH, .sshQuery: return true
        default: return false
        }
    }

    private var icon: String {
        switch item {
        case .plainTerminal: return "terminal"
        case .runQuery: return "arrow.right.circle"
        case .sshQuery, .pinned, .recentSSH: return "network"
        case .claudeFolder: return "sparkle"
        case .favorite: return "star.fill"
        case .recentCommand: return "clock"
        }
    }

    private var title: String {
        switch item {
        case .plainTerminal: return L.newTerminal
        case .runQuery(let cmd): return cmd
        case .sshQuery(let t): return "ssh \(t.displayTarget)"
        case .claudeFolder(let path): return L.openClaudeIn((path as NSString).lastPathComponent)
        case .favorite(let f): return f.displayName
        case .pinned(let t): return t.label ?? t.displayTarget
        case .recentSSH(let t): return t.displayTarget
        case .recentCommand(let rec): return rec.cmd ?? ""
        }
    }

    private var subtitle: String? {
        switch item {
        case .plainTerminal: return L.newTerminalSub
        case .runQuery: return L.runInNewTerminal
        case .sshQuery: return L.connectSSH
        case .claudeFolder(let path): return path
        case .favorite(let f):
            if f.label != nil { return f.command }
            return f.cwd ?? L.favoriteSub
        case .pinned(let t): return t.label != nil ? "ssh \(t.displayTarget)" : L.pinnedSub
        case .recentSSH: return L.recentSSHSub
        case .recentCommand(let rec): return rec.cwd
        }
    }
}

/// Чипы сводки: ssh-хосты кликабельны (реконнект), остальное — счётчики.
private struct FlowChips: View {
    let summary: ActivitySummary
    let onSSH: (SSHTarget) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(summary.sshTargets) { target in
                    Button { onSSH(target) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "network").font(.system(size: 9))
                            Text(target.displayTarget).font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(summary.kindCounts.filter { $0.kind != .ssh }, id: \.kind) { entry in
                    HStack(spacing: 4) {
                        Image(systemName: entry.kind.icon).font(.system(size: 9))
                        Text("\(entry.kind.title) ×\(entry.count)").font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
