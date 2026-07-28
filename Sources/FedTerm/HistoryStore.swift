import Foundation
import Combine

/// Пути хранения данных приложения.
enum AppPaths {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FedTerm", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var historyFile: URL { supportDir.appendingPathComponent("history.jsonl") }
    static var pinsFile: URL { supportDir.appendingPathComponent("pins.json") }
    static var stateFile: URL { supportDir.appendingPathComponent("state.json") }
    static var zdotdir: URL { supportDir.appendingPathComponent("zdotdir", isDirectory: true) }
}

/// Хранилище истории команд: читает history.jsonl (пишут zsh-хуки и само приложение),
/// следит за изменениями файла, отдаёт сессии, недавние ssh-цели и сводку за час.
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [CommandRecord] = []

    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var reloadPending = false

    init() {
        ensureFileExists()
        reload()
        startWatching()
    }

    deinit { stopWatching() }

    // MARK: - Запись событий из приложения (start/end сессии)

    func appendEvent(_ event: String, sid: String) {
        let line = "{\"ts\":\(Int(Date().timeIntervalSince1970)),\"sid\":\"\(sid)\",\"event\":\"\(event)\"}\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: AppPaths.historyFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    // MARK: - Чтение

    func reload() {
        guard let data = try? Data(contentsOf: AppPaths.historyFile),
              let text = String(data: data, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        var parsed: [CommandRecord] = []
        parsed.reserveCapacity(1024)
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let rec = try? decoder.decode(CommandRecord.self, from: lineData) else { continue }
            parsed.append(rec)
        }
        parsed.sort { $0.ts < $1.ts }
        DispatchQueue.main.async { self.records = parsed }
    }

    /// Последняя выполненная команда данной сессии (для отслеживания «этот таб сейчас в ssh»).
    func lastCommand(sid: String) -> CommandRecord? {
        records.last { $0.sid == sid && $0.event == nil && $0.cmd != nil }
    }

    /// Сессии, активные за интервал, свежие сверху.
    func sessions(within interval: TimeInterval) -> [SessionSummary] {
        let cutoff = Date().timeIntervalSince1970 - interval
        let relevant = records.filter { $0.ts >= cutoff }
        var bySid: [String: [CommandRecord]] = [:]
        for rec in relevant { bySid[rec.sid, default: []].append(rec) }
        return bySid.map { SessionSummary(sid: $0.key, records: $0.value) }
            .sorted { ($0.lastDate ?? .distantPast) > ($1.lastDate ?? .distantPast) }
    }

    /// Недавние ssh-цели по всей истории: сортировка по свежести, потом по частоте.
    func recentSSHTargets(limit: Int = 8) -> [SSHTarget] {
        var lastUse: [String: Double] = [:]
        var count: [String: Int] = [:]
        var byKey: [String: SSHTarget] = [:]
        for rec in records {
            guard let cmd = rec.cmd, let target = SSHTarget.parse(from: cmd) else { continue }
            let key = target.displayTarget
            byKey[key] = target
            lastUse[key] = max(lastUse[key] ?? 0, rec.ts)
            count[key, default: 0] += 1
        }
        return byKey.keys
            .sorted {
                let l0 = lastUse[$0] ?? 0, l1 = lastUse[$1] ?? 0
                if l0 != l1 { return l0 > l1 }
                return (count[$0] ?? 0) > (count[$1] ?? 0)
            }
            .prefix(limit)
            .compactMap { byKey[$0] }
    }

    /// Последние команды (свежие сверху), максимум limit. Служебные запуски клода
    /// (claude --resume/--session-id) отфильтрованы — они засоряют историю.
    func recentCommands(limit: Int = 200) -> [CommandRecord] {
        var out: [CommandRecord] = []
        for rec in records.reversed() {
            guard rec.event == nil, let cmd = rec.cmd else { continue }
            if cmd.hasPrefix("claude --resume") || cmd.hasPrefix("claude --session-id") { continue }
            out.append(rec)
            if out.count >= limit { break }
        }
        return out
    }

    /// Краткая сводка «что было за последний час» — по ключевым словам.
    func summary(within interval: TimeInterval = 3600, recentLimit: Int = 30) -> ActivitySummary {
        let cutoff = Date().timeIntervalSince1970 - interval
        let commands = records.filter { $0.ts >= cutoff && $0.event == nil && $0.cmd != nil }

        var seenSSH: [String: SSHTarget] = [:]
        var sshOrder: [String] = []
        var kinds: [CommandKind: Int] = [:]
        for rec in commands {
            guard let cmd = rec.cmd else { continue }
            let kind = CommandKind.classify(cmd)
            kinds[kind, default: 0] += 1
            if kind == .ssh, let target = SSHTarget.parse(from: cmd) {
                let key = target.displayTarget
                if seenSSH[key] == nil { sshOrder.append(key) }
                seenSSH[key] = target
            }
        }
        let kindCounts = kinds.sorted { $0.value > $1.value }.map { (kind: $0.key, count: $0.value) }
        return ActivitySummary(
            interval: interval,
            totalCommands: commands.count,
            sshTargets: sshOrder.reversed().compactMap { seenSSH[$0] }, // последние использованные — первыми
            kindCounts: kindCounts,
            recent: commands.suffix(recentLimit).reversed()
        )
    }

    // MARK: - Наблюдение за файлом

    private func ensureFileExists() {
        let path = AppPaths.historyFile.path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
    }

    private func startWatching() {
        let fd = open(AppPaths.historyFile.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend], queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func scheduleReload() {
        DispatchQueue.main.async {
            guard !self.reloadPending else { return }
            self.reloadPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.reloadPending = false
                DispatchQueue.global(qos: .utility).async { self.reload() }
            }
        }
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }
}

/// Закреплённые (сохранённые) ssh-подключения — «всегда на главной».
final class PinsStore: ObservableObject {
    @Published private(set) var pins: [SSHTarget] = []

    init() { load() }

    func isPinned(_ target: SSHTarget) -> Bool {
        pins.contains { $0.displayTarget == target.displayTarget }
    }

    func toggle(_ target: SSHTarget) {
        if isPinned(target) {
            pins.removeAll { $0.displayTarget == target.displayTarget }
        } else {
            pins.append(target)
        }
        save()
    }

    func rename(_ target: SSHTarget, label: String?) {
        guard let idx = pins.firstIndex(where: { $0.displayTarget == target.displayTarget }) else { return }
        pins[idx].label = (label?.isEmpty == true) ? nil : label
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.pinsFile),
              let decoded = try? JSONDecoder().decode([SSHTarget].self, from: data) else { return }
        pins = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pins) else { return }
        try? data.write(to: AppPaths.pinsFile, options: .atomic)
    }
}
