import Foundation
import Combine

/// Избранная команда: звёздочка на любой команде; «заклёпка» (autorun) —
/// команда автоматически открывается в своей вкладке при запуске аппки.
struct FavoriteCommand: Codable, Identifiable, Hashable {
    var id = UUID()
    var command: String
    var cwd: String?
    var autorun: Bool = false
    /// Имя, заданное пользователем (карандаш на строке).
    var label: String?

    var displayName: String {
        if let label, !label.isEmpty { return label }
        return command
    }
}

extension AppPaths {
    static var favoritesFile: URL { supportDir.appendingPathComponent("favorites.json") }
}

final class FavoritesStore: ObservableObject {
    @Published private(set) var favorites: [FavoriteCommand] = []

    init() { load() }

    func isFavorite(_ command: String) -> Bool {
        favorites.contains { $0.command == command }
    }

    func favorite(for command: String) -> FavoriteCommand? {
        favorites.first { $0.command == command }
    }

    func toggle(command: String, cwd: String?) {
        if let idx = favorites.firstIndex(where: { $0.command == command }) {
            favorites.remove(at: idx)
        } else {
            favorites.append(FavoriteCommand(command: command, cwd: cwd))
        }
        save()
    }

    func rename(_ id: UUID, label: String?) {
        guard let idx = favorites.firstIndex(where: { $0.id == id }) else { return }
        favorites[idx].label = (label?.isEmpty == true) ? nil : label
        save()
    }

    func toggleAutorun(_ id: UUID) {
        guard let idx = favorites.firstIndex(where: { $0.id == id }) else { return }
        favorites[idx].autorun.toggle()
        save()
    }

    func remove(_ id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.favoritesFile),
              let decoded = try? JSONDecoder().decode([FavoriteCommand].self, from: data) else { return }
        favorites = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        try? data.write(to: AppPaths.favoritesFile, options: .atomic)
    }
}
