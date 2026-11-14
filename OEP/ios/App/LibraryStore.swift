// OEP - library persistence.
//
// Games live in Application Support/OEP/Games/<folder>.  library.json keeps the
// metadata; both are inside the app container so the original import source is
// never touched after copying.
import Foundation

final class LibraryStore: ObservableObject {
    @Published private(set) var games: [GameEntry] = []
    @Published private(set) var lastError: String?

    let rootURL: URL
    let gamesURL: URL

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var libraryURL: URL { rootURL.appendingPathComponent("library.json") }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        rootURL = support.appendingPathComponent("OEP", isDirectory: true)
        gamesURL = rootURL.appendingPathComponent("Games", isDirectory: true)
        try? fileManager.createDirectory(at: gamesURL, withIntermediateDirectories: true)
        load()
    }

    func folder(for game: GameEntry) -> URL {
        gamesURL.appendingPathComponent(game.folderName, isDirectory: true)
    }

    func load() {
        guard fileManager.fileExists(atPath: libraryURL.path) else {
            games = []
            OEPCore.log(1, "library", "no library.json yet (fresh install)")
            return
        }
        do {
            let data = try Data(contentsOf: libraryURL)
            games = try decoder.decode([GameEntry].self, from: data)
            OEPCore.log(1, "library", "loaded \(games.count) game(s)")
        } catch {
            lastError = error.localizedDescription
            games = []
            OEPCore.log(3, "library", "library.json could not be read: \(error.localizedDescription)")
        }
    }

    func save() {
        do {
            let data = try encoder.encode(games)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
            OEPCore.log(3, "library", "library.json could not be written: \(error.localizedDescription)")
        }
    }

    // MARK: - Mutations

    func add(_ game: GameEntry) {
        games.append(game)
        sortInPlace()
        save()
    }

    func update(_ game: GameEntry) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index] = game
        save()
    }

    func toggleFavorite(_ game: GameEntry) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index].isFavorite.toggle()
        save()
    }

    @discardableResult
    func remove(_ game: GameEntry, deleteFiles: Bool) -> Error? {
        if deleteFiles {
            let url = folder(for: game)
            do {
                try fileManager.removeItem(at: url)
            } catch {
                OEPCore.log(3, "library", "could not delete \(url.lastPathComponent): \(error.localizedDescription)")
                return error
            }
        }
        games.removeAll { $0.id == game.id }
        save()
        return nil
    }

    func duplicate(of signature: String) -> GameEntry? {
        guard !signature.isEmpty else { return nil }
        return games.first { $0.signature == signature }
    }

    func recordSessionStart(_ game: GameEntry) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index].lastPlayedAt = Date()
        games[index].launchCount += 1
        save()
    }

    func recordPlaytime(_ gameID: UUID, seconds: TimeInterval) {
        guard seconds > 0, let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].playtime += seconds
        save()
    }

    // MARK: - Queries

    func game(id: UUID) -> GameEntry? { games.first { $0.id == id } }

    var totalPlaytime: TimeInterval { games.reduce(0) { $0 + $1.playtime } }

    var totalBytes: Int64 { games.reduce(0) { $0 + $1.totalBytes } }

    var lastPlayed: GameEntry? {
        games.filter { $0.lastPlayedAt != nil }
            .max { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }
    }

    func filtered(sort: LibrarySort, favoritesOnly: Bool, query: String) -> [GameEntry] {
        var result = games
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                    || $0.engineTitle.localizedCaseInsensitiveContains(trimmed)
                    || $0.engineVersion.localizedCaseInsensitiveContains(trimmed)
            }
        }
        if favoritesOnly {
            result = result.filter(\.isFavorite)
        }
        switch sort {
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .lastPlayed:
            result.sort { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        case .imported:
            result.sort { $0.importedAt > $1.importedAt }
        case .size:
            result.sort { $0.totalBytes > $1.totalBytes }
        }
        return result
    }

    private func sortInPlace() {
        games.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // MARK: - Storage

    func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    var cacheBytes: Int64 {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let caches else { return 0 }
        return directorySize(caches.appendingPathComponent("OEP", isDirectory: true))
    }

    @discardableResult
    func clearCaches() -> Int64 {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let caches else { return 0 }
        let target = caches.appendingPathComponent("OEP", isDirectory: true)
        let before = directorySize(target)
        try? fileManager.removeItem(at: target)
        try? fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        OEPCore.log(1, "library", "cleared caches (\(before) bytes)")
        return before
    }
}

// MARK: - Settings

final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private static let key = "oep.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
