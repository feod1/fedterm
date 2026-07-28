import SwiftUI

/// Фирменный оранжевый клода.
let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

/// Оверлей «как назвать сессию» — появляется после drop папки или ввода пути.
struct ClaudeNameOverlay: View {
    let folder: URL
    @EnvironmentObject var claude: ClaudeSessionsStore
    @EnvironmentObject var tabs: TabsModel
    @State private var name = ""
    @State private var wasPinned = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .onTapGesture { cancel() }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .foregroundStyle(claudeOrange)
                    Text(L.newClaudeSession)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(folder.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                TextField(L.sessionName, text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                    .focused($focused)
                    .onSubmit { confirm() }
                    .onExitCommand { cancel() }
                HStack {
                    Spacer()
                    Button(L.cancel) { cancel() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Button {
                        confirm()
                    } label: {
                        Text(L.openClaude)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(claudeOrange.opacity(0.9)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .padding(20)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: NSColor(hex: 0x24282E)))
                    .shadow(radius: 30)
            )
        }
        .onAppear {
            name = folder.lastPathComponent
            PanelBridge.shared.editingText = true
            wasPinned = PanelBridge.shared.pinned
            PanelBridge.shared.pinned = true
            DispatchQueue.main.async { focused = true }
        }
        .onDisappear {
            PanelBridge.shared.editingText = false
            PanelBridge.shared.pinned = wasPinned
        }
    }

    private func confirm() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let record = claude.create(name: trimmed.isEmpty ? folder.lastPathComponent : trimmed, path: folder.path)
        claude.pendingFolder = nil
        let homeTab = (tabs.selectedTab?.isHome == true) ? tabs.selectedTab : nil
        tabs.openClaude(record: record, in: homeTab)
    }

    private func cancel() {
        claude.pendingFolder = nil
    }
}

/// Кнопка с иконкой клода: поповер со всеми сессиями по проектам.
struct ClaudeMenuButton: View {
    @EnvironmentObject var claude: ClaudeSessionsStore
    @EnvironmentObject var tabs: TabsModel
    @State private var showPopover = false

    var body: some View {
        Button { showPopover.toggle() } label: {
            Image(systemName: "sparkle")
                .font(.system(size: 12))
                .foregroundStyle(claudeOrange)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L.claudeSessionsHelp)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ClaudeSessionsPopover(dismiss: { showPopover = false })
                .environmentObject(claude)
                .environmentObject(tabs)
        }
    }
}

/// Поповер сессий: «Сохранённые» (по папкам-проектам) и «Вся история» (по свежести).
struct ClaudeSessionsPopover: View {
    let dismiss: () -> Void
    @EnvironmentObject var claude: ClaudeSessionsStore
    @EnvironmentObject var tabs: TabsModel
    @State private var mode = 0   // 0 — сохранённые, 1 — вся история
    @State private var searchText = ""
    @State private var visibleCount = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(claudeOrange).font(.system(size: 11))
                Picker("", selection: $mode) {
                    Text(L.savedSegment).tag(0)
                    Text(L.historySegment).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                Button { createNewSession() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 11))
                        Text(L.newSession).font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(claudeOrange.opacity(0.85)))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help(L.newSessionHelp)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField(L.searchSessions, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            if mode == 0 {
                savedList
            } else {
                historyList
            }
        }
        .frame(width: 420)
        .frame(minHeight: 380, maxHeight: 860)
        .onAppear { claude.refreshDiscovered() }
        .onChange(of: searchText) { _ in visibleCount = 40 }
        .onChange(of: mode) { _ in visibleCount = 40 }
    }

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// «Новая сессия»: выбор папки в Finder-диалоге → оверлей имени → создание и запуск.
    private func createNewSession() {
        dismiss()
        PanelBridge.shared.suppressHide = true
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = true
        openPanel.prompt = L.choose
        openPanel.message = L.newSessionHelp
        NSApp.activate(ignoringOtherApps: true)
        let result = openPanel.runModal()
        PanelBridge.shared.suppressHide = false
        PanelBridge.shared.show()
        if result == .OK, let url = openPanel.url {
            claude.pendingFolder = url
        }
    }

    private func open(record: ClaudeSessionRecord) {
        let homeTab = (tabs.selectedTab?.isHome == true) ? tabs.selectedTab : nil
        tabs.openClaude(record: record, in: homeTab)
        dismiss()
    }

    private func open(session: DiscoveredSession) {
        // если у сессии есть именованная запись — открываем через неё
        if let record = claude.savedRecord(sessionID: session.id) {
            open(record: record)
            return
        }
        let homeTab = (tabs.selectedTab?.isHome == true) ? tabs.selectedTab : nil
        tabs.openClaudeSession(session, in: homeTab)
        dismiss()
    }

    // MARK: - Сохранённые (по проектам)

    private var filteredSavedGroups: [(path: String, items: [ClaudeSessionRecord])] {
        let q = normalizedQuery
        guard !q.isEmpty else { return claude.byProject }
        return claude.byProject.compactMap { group in
            let items = group.items.filter {
                $0.name.lowercased().contains(q)
                    || group.path.lowercased().contains(q)
            }
            return items.isEmpty ? nil : (group.path, items)
        }
    }

    @ViewBuilder
    private var savedList: some View {
        if claude.sessions.isEmpty {
            VStack(spacing: 6) {
                Text(L.noSavedSessions)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(L.noSavedHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredSavedGroups, id: \.path) { group in
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text((group.path as NSString).lastPathComponent)
                                .font(.system(size: 10, weight: .semibold))
                            Text(group.path)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 2)

                        ForEach(group.items) { record in
                            ClaudeSessionRow(record: record) {
                                open(record: record)
                            } onDelete: {
                                claude.delete(record.id)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Вся история (по свежести: 24 часа / 7 дней / месяц / ранее)

    /// Фильтр по поиску + порционный показ (visibleCount штук за раз).
    private var filteredHistory: [DiscoveredSession] {
        let q = normalizedQuery
        guard !q.isEmpty else { return claude.discovered }
        return claude.discovered.filter { session in
            session.title.lowercased().contains(q)
                || session.path.lowercased().contains(q)
                || (claude.savedRecord(sessionID: session.id)?.name.lowercased().contains(q) ?? false)
        }
    }

    private var buckets: [(label: String, items: [DiscoveredSession])] {
        let now = Date()
        var day: [DiscoveredSession] = [], week: [DiscoveredSession] = []
        var month: [DiscoveredSession] = [], earlier: [DiscoveredSession] = []
        for s in filteredHistory.prefix(visibleCount) {
            let age = now.timeIntervalSince(s.lastModified)
            if age < 86_400 { day.append(s) }
            else if age < 7 * 86_400 { week.append(s) }
            else if age < 30 * 86_400 { month.append(s) }
            else { earlier.append(s) }
        }
        return [
            (L.last24h, day),
            (L.last7d, week),
            (L.lastMonth, month),
            (L.earlier, earlier),
        ].filter { !$0.1.isEmpty }
    }

    /// Внутри временной группы — раскладка по папкам-проектам (порядок — по свежести).
    private func projectGroups(_ items: [DiscoveredSession]) -> [(path: String, items: [DiscoveredSession])] {
        var order: [String] = []
        var map: [String: [DiscoveredSession]] = [:]
        for session in items {
            if map[session.path] == nil { order.append(session.path) }
            map[session.path, default: []].append(session)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    @ViewBuilder
    private var historyList: some View {
        if claude.discovered.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if filteredHistory.isEmpty {
            Text(L.nothingFound(searchText))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(buckets, id: \.label) { bucket in
                        Text(bucket.label.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(claudeOrange.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 2)
                        ForEach(projectGroups(bucket.items), id: \.path) { group in
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text((group.path as NSString).lastPathComponent)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(group.path)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, 1)
                            ForEach(group.items) { session in
                                DiscoveredSessionRow(
                                    session: session,
                                    savedName: claude.savedRecord(sessionID: session.id)?.name,
                                    onOpen: { open(session: session) },
                                    onSave: {
                                        claude.create(name: session.title, path: session.path, sessionID: session.id)
                                    }
                                )
                            }
                        }
                    }
                    if filteredHistory.count > visibleCount {
                        Button {
                            visibleCount += 60
                        } label: {
                            Text(L.showMore(filteredHistory.count - visibleCount))
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

/// Строка исторической сессии с диска.
private struct DiscoveredSessionRow: View {
    let session: DiscoveredSession
    let savedName: String?
    let onOpen: () -> Void
    let onSave: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 10))
                .foregroundStyle(claudeOrange.opacity(0.85))
            VStack(alignment: .leading, spacing: 1) {
                Text(savedName ?? session.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(session.lastModified, format: .relative(presentation: .named))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onSave) {
                Image(systemName: savedName != nil ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(savedName != nil ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(savedName != nil)
            .opacity(hovering || savedName != nil ? 1 : 0)
            .help(savedName != nil ? L.alreadySaved : L.saveForever)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color.white.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering = $0 }
    }
}

private struct ClaudeSessionRow: View {
    let record: ClaudeSessionRecord
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 10))
                .foregroundStyle(claudeOrange.opacity(0.85))
            VStack(alignment: .leading, spacing: 1) {
                Text(record.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(record.lastUsedAt, format: .relative(presentation: .named))
                    if record.claudeSessionID != nil {
                        Text(L.resumes)
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help(L.deleteFromList)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color.white.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering = $0 }
    }
}
