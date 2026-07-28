import Foundation
import Combine

/// Сессия Claude Code, привязанная к проекту: имя, папка, id сессии клода.
/// Хранится навсегда (до ручного удаления) и переживает перезапуски.
struct ClaudeSessionRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var claudeSessionID: String?
    var createdAt: Date
    var lastUsedAt: Date

    var folderName: String { (path as NSString).lastPathComponent }
}

extension AppPaths {
    static var claudeSessionsFile: URL { supportDir.appendingPathComponent("claude_sessions.json") }
    static var claudeIndexFile: URL { supportDir.appendingPathComponent("claude_index.json") }
    static var claudeProjectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }
}

/// Сессия Claude Code, найденная на диске (в ~/.claude/projects) — всё, что когда-либо было.
struct DiscoveredSession: Identifiable, Hashable {
    var id: String          // uuid сессии (= имя jsonl-файла)
    var path: String        // cwd проекта (вычитан из jsonl)
    var lastModified: Date
    var title: String       // саммари или первое сообщение пользователя
}

final class ClaudeSessionsStore: ObservableObject {
    @Published private(set) var sessions: [ClaudeSessionRecord] = []
    /// Все сессии с диска, свежие сверху.
    @Published private(set) var discovered: [DiscoveredSession] = []
    /// Папка, ожидающая имени (после drop или ввода пути) — открывает оверлей.
    @Published var pendingFolder: URL?

    /// Персистентный индекс заголовков: перечитываем jsonl только если файл изменился.
    private struct IndexEntry: Codable {
        var mtime: TimeInterval
        var title: String
        var cwd: String
    }

    private var titleCache: [String: IndexEntry] = [:]   // только на scanQueue
    private var indexLoaded = false
    private var indexDirty = false
    private let scanQueue = DispatchQueue(label: "fedterm.claude.scan")

    init() { load() }

    // MARK: - CRUD

    /// Session id мы задаём САМИ при создании записи (claude --session-id) —
    /// никакого угадывания и захвата, привязка железная с первого запуска.
    @discardableResult
    func create(name: String, path: String, sessionID: String? = nil) -> ClaudeSessionRecord {
        let sid = sessionID ?? UUID().uuidString.lowercased()
        let rec = ClaudeSessionRecord(name: name, path: path, claudeSessionID: sid, createdAt: Date(), lastUsedAt: Date())
        sessions.append(rec)
        save()
        return rec
    }

    /// Команда запуска записи: если сессия уже есть на диске — резюмим,
    /// если нет (первый запуск или первый не успел записаться) — создаём с нашим id.
    func launchCommand(for record: ClaudeSessionRecord) -> String {
        guard let sid = record.claudeSessionID else { return "claude" } // легаси-записи
        return Self.sessionFileExists(id: sid, projectPath: record.path)
            ? "claude --resume \(sid)"
            : "claude --session-id \(sid)"
    }

    static func sessionFileExists(id: String, projectPath: String) -> Bool {
        for encoded in encodedCandidates(projectPath) {
            let file = AppPaths.claudeProjectsDir
                .appendingPathComponent(encoded)
                .appendingPathComponent("\(id).jsonl")
            if FileManager.default.fileExists(atPath: file.path) { return true }
        }
        return false
    }

    /// Именованная запись, привязанная к этой сессии клода (если есть).
    func savedRecord(sessionID: String) -> ClaudeSessionRecord? {
        sessions.first { $0.claudeSessionID == sessionID }
    }

    func record(id: UUID) -> ClaudeSessionRecord? {
        sessions.first { $0.id == id }
    }

    func markUsed(_ id: UUID) {
        update(id) { $0.lastUsedAt = Date() }
    }

    func rename(_ id: UUID, name: String) {
        update(id) { $0.name = name }
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    /// Сессии, разложенные по папкам-проектам (свежие проекты сверху).
    var byProject: [(path: String, items: [ClaudeSessionRecord])] {
        Dictionary(grouping: sessions, by: { $0.path })
            .map { (path: $0.key, items: $0.value.sorted { $0.lastUsedAt > $1.lastUsedAt }) }
            .sorted { ($0.items.first?.lastUsedAt ?? .distantPast) > ($1.items.first?.lastUsedAt ?? .distantPast) }
    }

    private func update(_ id: UUID, _ mutate: (inout ClaudeSessionRecord) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&sessions[idx])
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.claudeSessionsFile),
              let decoded = try? JSONDecoder().decode([ClaudeSessionRecord].self, from: data) else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: AppPaths.claudeSessionsFile, options: .atomic)
    }

    // MARK: - Скан всей истории Claude Code на диске

    /// Пересканировать ~/.claude/projects (в фоне; результат прилетит в published discovered).
    func refreshDiscovered() {
        scanQueue.async { [weak self] in
            guard let self else { return }
            let result = self.scanDisk()
            DispatchQueue.main.async { self.discovered = result }
        }
    }

    /// Индексируем не больше стольки самых свежих сессий — старьё дальше не читаем.
    private static let indexLimit = 200

    private func scanDisk() -> [DiscoveredSession] {
        loadIndexIfNeeded()
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: AppPaths.claudeProjectsDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        // 1) дешёвый проход: только пути и mtime, без чтения содержимого
        var candidates: [(file: URL, mtime: Date, dirName: String)] = []
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let mtime = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                else { continue }
                candidates.append((file, mtime, dir.lastPathComponent))
            }
        }

        // 2) берём только свежайшие indexLimit и парсим заголовки (с кэшем)
        candidates.sort { $0.mtime > $1.mtime }
        let top = candidates.prefix(Self.indexLimit)
        var out: [DiscoveredSession] = []
        var seen = Set<String>()
        for item in top {
            seen.insert(item.file.path)
            let sid = item.file.deletingPathExtension().lastPathComponent
            let meta = titleAndCwd(for: item.file, mtime: item.mtime, fallbackDir: item.dirName)
            out.append(DiscoveredSession(id: sid, path: meta.cwd, lastModified: item.mtime, title: meta.title))
        }

        // подчистить индекс от удалённых/выпавших за лимит файлов
        let stale = titleCache.keys.filter { !seen.contains($0) }
        if !stale.isEmpty {
            for key in stale { titleCache.removeValue(forKey: key) }
            indexDirty = true
        }
        saveIndexIfDirty()
        return out
    }

    private func loadIndexIfNeeded() {
        guard !indexLoaded else { return }
        indexLoaded = true
        guard let data = try? Data(contentsOf: AppPaths.claudeIndexFile),
              let decoded = try? JSONDecoder().decode([String: IndexEntry].self, from: data) else { return }
        titleCache = decoded
    }

    private func saveIndexIfDirty() {
        guard indexDirty else { return }
        indexDirty = false
        if let data = try? JSONEncoder().encode(titleCache) {
            try? data.write(to: AppPaths.claudeIndexFile, options: .atomic)
        }
    }

    /// Заголовок и cwd — из первых строк jsonl: summary-строка либо первое сообщение пользователя.
    private func titleAndCwd(for file: URL, mtime: Date, fallbackDir: String) -> (title: String, cwd: String) {
        if let cached = titleCache[file.path], abs(cached.mtime - mtime.timeIntervalSince1970) < 0.5 {
            return (cached.title, cached.cwd)
        }
        var summary: String?
        var firstUserText: String?
        var cwd: String?
        if let handle = try? FileHandle(forReadingFrom: file) {
            let data = (try? handle.read(upToCount: 131_072)) ?? Data()
            try? handle.close()
            if let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                    else { continue }
                    if cwd == nil, let c = obj["cwd"] as? String { cwd = c }
                    if summary == nil, let s = obj["summary"] as? String { summary = s }
                    if firstUserText == nil, obj["type"] as? String == "user",
                       let msg = obj["message"] as? [String: Any] {
                        var candidate: String?
                        if let s = msg["content"] as? String {
                            candidate = s
                        } else if let arr = msg["content"] as? [[String: Any]] {
                            candidate = arr.compactMap { $0["text"] as? String }.first
                        }
                        // служебные сообщения (<command-name>… и т.п.) заголовком не считаем
                        if let c = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !c.isEmpty, !c.hasPrefix("<") {
                            firstUserText = c
                        }
                    }
                    if cwd != nil && summary != nil { break }
                }
            }
        }
        var title = (summary ?? firstUserText ?? fallbackDir)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if title.count > 70 { title = String(title.prefix(70)) + "…" }
        let cwdFinal = cwd ?? fallbackDir.replacingOccurrences(of: "-", with: "/")
        titleCache[file.path] = IndexEntry(mtime: mtime.timeIntervalSince1970, title: title, cwd: cwdFinal)
        indexDirty = true
        return (title, cwdFinal)
    }

    // MARK: - Захват session id Claude Code

    /// Основной источник: реестр живых сессий ~/.claude/sessions/<pid>.json —
    /// появляется сразу при старте клода и содержит sessionId + cwd. Мы ищем запись,
    /// чей процесс — потомок шелла нашей вкладки. Фолбэк — новый jsonl в ~/.claude/projects.
    func scheduleCapture(for recordID: UUID, launchedAt: Date, shellPID: pid_t?) {
        for delay in [3.0, 6, 12, 25, 60, 150] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let rec = self.record(id: recordID) else { return }
                // id уже пойман для этого запуска — дальше не дёргаемся
                if rec.claudeSessionID != nil, rec.lastUsedAt >= launchedAt { return }
                self.captureNow(recordID: recordID, launchedAt: launchedAt, shellPID: shellPID)
            }
        }
    }

    func captureNow(recordID: UUID, launchedAt: Date, shellPID: pid_t?) {
        guard let rec = record(id: recordID) else { return }
        // id теперь задаётся при создании — захват нужен только легаси-записям без id
        guard rec.claudeSessionID == nil else { return }
        var found: String?
        if let shellPID {
            found = Self.liveSessionID(underShell: shellPID)
        }
        if found == nil {
            found = Self.newestSessionID(projectPath: rec.path, since: launchedAt)
        }
        guard let found, found != rec.claudeSessionID else { return }
        update(recordID) { $0.claudeSessionID = found; $0.lastUsedAt = Date() }
    }

    // MARK: реестр живых сессий

    private struct LiveSession: Decodable {
        let pid: Int32
        let sessionId: String
        let cwd: String?
    }

    /// sessionId клода, запущенного внутри данного шелла (по цепочке родительских процессов).
    static func liveSessionID(underShell shellPID: pid_t) -> String? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return nil }
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let live = try? decoder.decode(LiveSession.self, from: data) else { continue }
            guard kill(live.pid, 0) == 0 else { continue } // процесс должен быть жив
            if isProcess(live.pid, descendantOf: shellPID) {
                return live.sessionId
            }
        }
        return nil
    }

    private static func parentPID(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }

    private static func isProcess(_ pid: pid_t, descendantOf ancestor: pid_t) -> Bool {
        var current = pid
        for _ in 0..<12 {
            if current == ancestor { return true }
            if current <= 1 { return false }
            current = parentPID(of: current)
            if current == 0 { return false }
        }
        return false
    }

    /// Важно: фильтруем по дате СОЗДАНИЯ файла, а не изменения — в той же папке может
    /// параллельно жить другая активная сессия Claude (например, запущенная не из FedTerm),
    /// и она постоянно дописывает свой jsonl. Наш же запуск всегда создаёт новый файл.
    static func newestSessionID(projectPath: String, since: Date) -> String? {
        for encoded in encodedCandidates(projectPath) {
            let dir = AppPaths.claudeProjectsDir.appendingPathComponent(encoded)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.creationDateKey]
            ) else { continue }
            let newest = files
                .filter { $0.pathExtension == "jsonl" }
                .compactMap { url -> (String, Date)? in
                    guard let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
                    else { return nil }
                    return (url.deletingPathExtension().lastPathComponent, date)
                }
                .filter { $0.1 > since.addingTimeInterval(-2) }
                .max { $0.1 < $1.1 }
            if let newest { return newest.0 }
        }
        return nil
    }

    /// Кодирование пути как у Claude Code: "/" и "." → "-" (на всякий случай пробуем и с "_").
    private static func encodedCandidates(_ path: String) -> [String] {
        let primary = String(path.map { $0 == "/" || $0 == "." ? "-" : $0 })
        let alt = String(path.map { $0 == "/" || $0 == "." || $0 == "_" ? "-" : $0 })
        return primary == alt ? [primary] : [primary, alt]
    }
}
