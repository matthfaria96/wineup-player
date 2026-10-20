import Foundation
import WineupLibrary

/// Adaptador simples entre o app e a biblioteca persistida (WineupLibrary).
@MainActor
final class LibraryController {
    nonisolated let isAvailable: Bool
    nonisolated let database: LibraryDatabase?
    /// Presets de EQ no mesmo banco do app (respeita WINEUP_LIBRARY_PATH).
    nonisolated var presetStore: EqPresetStore? { database.map(EqPresetStore.init(db:)) }
    private var scanTask: Task<Void, Never>?
    private var onTracks: (([LibraryTrack]) -> Void)?
    private var onStatus: ((String?) -> Void)?

    nonisolated init(databasePath: String? = nil) {
        let override = ProcessInfo.processInfo.environment["WINEUP_LIBRARY_PATH"]
        let opened = try? LibraryDatabase(path: databasePath ?? override ?? LibraryDatabase.defaultPath())
        database = opened
        isAvailable = opened != nil
    }

    /// Primeira abertura (NAV-01), carga da biblioteca persistida e varredura das raízes.
    func start(onTracks: @escaping ([LibraryTrack]) -> Void, onStatus: @escaping (String?) -> Void) async {
        guard let database else { onStatus("Biblioteca indisponível"); return }
        self.onTracks = onTracks
        self.onStatus = onStatus
        _ = try? LibraryBootstrap.ensureDefaultRoot(database: database)
        await reload()
        beginScan(rootIDs: nil)
    }

    func addFolders(_ urls: [URL]) async {
        guard let database else { return }
        let store = LibraryRootStore(db: database)
        var added = false
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if (try? store.addRoot(url)) != nil { added = true }
        }
        if added { beginScan(rootIDs: nil) } else { onStatus?("Nenhuma pasta válida para adicionar.") }
    }

    func search(_ text: String) async -> [LibraryTrack] {
        guard let database else { return [] }
        return (try? await SearchService(database: database).search(text, limit: 200)) ?? []
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
    }

    private func reload() async {
        guard let database else { return }
        let tracks = (try? await BrowseService(database: database).allTracks(limit: 5000, offset: 0)) ?? []
        onTracks?(tracks)
    }

    private func beginScan(rootIDs: [UUID]?) {
        guard let database else { return }
        cancelScan()
        scanTask = Task { [weak self] in
            let roots = (try? LibraryRootStore(db: database).roots()) ?? []
            let scanner = WineupLibrary.Scanner(database: database)
            for root in roots where rootIDs?.contains(root.id) ?? true {
                if Task.isCancelled { return }
                do {
                    for try await progress in scanner.scan(rootID: root.id) {
                        self?.onStatus?("Varrendo biblioteca: \(progress.read)/\(progress.toRead)")
                    }
                } catch {
                    self?.onStatus?("Falha ao varrer uma pasta da biblioteca.")
                }
            }
            guard !Task.isCancelled else { return }
            await self?.reload()
            self?.onStatus?(nil)
        }
    }
}
