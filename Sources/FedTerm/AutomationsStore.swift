import Foundation
import Combine

/// Automation: a bash command with a ⌘1–⌘9 hotkey. Hotkeys work only
/// while the FedTerm window is open and are not passed to the system/other apps.
struct Automation: Codable, Identifiable, Hashable {
    var id = UUID()
    var command: String
    var key: Int          // 1...9 → ⌘1...⌘9
    var cwd: String?      // working directory (home by default)

    var expandedCwd: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return NSString(string: cwd).expandingTildeInPath
    }
}

extension AppPaths {
    static var automationsFile: URL { supportDir.appendingPathComponent("automations.json") }
    static var scriptsDir: URL { supportDir.appendingPathComponent("scripts", isDirectory: true) }
}

final class AutomationsStore: ObservableObject {
    static let shared = AutomationsStore()

    @Published private(set) var automations: [Automation] = []
    /// Whether the builder overlay is open (lives on top of the window — survives system dialogs).
    @Published var editorVisible = false

    private init() { load() }

    func automation(forKey key: Int) -> Automation? {
        automations.first { $0.key == key }
    }

    var freeKeys: [Int] {
        let used = Set(automations.map(\.key))
        return (1...9).filter { !used.contains($0) }
    }

    func add(command: String, key: Int, cwd: String?) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, (1...9).contains(key), automation(forKey: key) == nil else { return }
        let dir = cwd?.trimmingCharacters(in: .whitespaces)
        automations.append(Automation(command: trimmed, key: key, cwd: (dir?.isEmpty == true) ? nil : dir))
        automations.sort { $0.key < $1.key }
        save()
    }

    func remove(_ id: UUID) {
        automations.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: AppPaths.scriptsDir.appendingPathComponent("\(id.uuidString).sh"))
        save()
    }

    /// Launch command: a one-liner runs as is; a multiline bash script
    /// is saved to a .sh file and run via bash (otherwise line-by-line input would break constructs).
    func launchCommand(for automation: Automation) -> String {
        guard automation.command.contains("\n") else { return automation.command }
        try? FileManager.default.createDirectory(at: AppPaths.scriptsDir, withIntermediateDirectories: true)
        let file = AppPaths.scriptsDir.appendingPathComponent("\(automation.id.uuidString).sh")
        let content = "#!/bin/bash\n" + automation.command + "\n"
        try? content.write(to: file, atomically: true, encoding: .utf8)
        return "bash '\(file.path)'"
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.automationsFile),
              let decoded = try? JSONDecoder().decode([Automation].self, from: data) else { return }
        automations = decoded.sorted { $0.key < $1.key }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(automations) else { return }
        try? data.write(to: AppPaths.automationsFile, options: .atomic)
    }
}
