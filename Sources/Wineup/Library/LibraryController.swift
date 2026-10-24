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
    /// Vigia as raízes: mudanças no disco disparam varredura incremental automática.
    private lazy var watcher = FolderWatcher { [weak self] paths in self?.folderChanged(paths) }
    /// Raízes a varrer quando a varredura atual terminar (nil = todas).
    private var pendingRoots: Set<UUID>?
    private var hasPending = false
    /// `start` roda uma vez só (reabrir a janela não carrega nem varre tudo de novo).
    private var started = false
    private var onChange: (() -> Void)?
    private var onStatus: ((String?) -> Void)?

    nonisolated init(databasePath: String? = nil) {
        let override = ProcessInfo.processInfo.environment["WINEUP_LIBRARY_PATH"]
        let opened = try? LibraryDatabase(path: databasePath ?? override ?? LibraryDatabase.defaultPath())
        database = opened
        isAvailable = opened != nil
    }

    /// Primeira abertura (NAV-01), carga da biblioteca persistida e varredura das raízes.
    func start(onChange: @escaping () -> Void, onStatus: @escaping (String?) -> Void) async {
        guard let database else { onStatus(String(localized: "Biblioteca indisponível")); return }
        guard !started else { return }
        started = true
        self.onChange = onChange
        self.onStatus = onStatus
        if ProcessInfo.processInfo.environment["WINEUP_DEFAULT_FOLDER"] == nil {
            _ = try? LibraryBootstrap.ensureDefaultRoot(database: database)
        }
        await reload()
        // Medições: WINEUP_NO_SCAN=1 não varre na abertura (biblioteca sintética sem arquivos).
        if ProcessInfo.processInfo.environment["WINEUP_NO_SCAN"] == nil {
            beginScan(rootIDs: nil)
            watchRoots()
        }
    }

    private func watchRoots() {
        guard let database else { return }
        let paths = ((try? LibraryRootStore(db: database).roots()) ?? []).map(\.url.path)
        watcher.watch(paths)
    }

    /// Algo mudou numa pasta vigiada: varre de novo só as raízes afetadas (ou marca para o fim da atual).
    private func folderChanged(_ paths: [String]) {
        guard let database else { return }
        let roots = (try? LibraryRootStore(db: database).roots()) ?? []
        let affected = Set(roots.filter { root in
            let prefix = root.url.path.hasSuffix("/") ? root.url.path : root.url.path + "/"
            return paths.isEmpty || paths.contains { $0 == root.url.path || $0.hasPrefix(prefix) }
        }.map(\.id))
        guard !affected.isEmpty else { return }
        if scanTask != nil {
            if hasPending { pendingRoots = pendingRoots.map { $0.union(affected) } } else { pendingRoots = affected }
            hasPending = true
        } else {
            beginScan(rootIDs: Array(affected))
        }
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
        if added { beginScan(rootIDs: nil); watchRoots() } else { onStatus?(String(localized: "Nenhuma pasta válida para adicionar.")) }
    }

    func search(_ text: String) async -> [LibraryTrack] {
        guard let database else { return [] }
        return (try? await SearchService(database: database).search(text, limit: 200)) ?? []
    }

    /// Varre de novo todas as raízes (botão Atualizar).
    func rescan() { beginScan(rootIDs: nil) }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
    }

    /// Avisa que a biblioteca mudou (a lista é relida pelo navegador; não carrega todas as faixas aqui).
    private func reload() async {
        guard database != nil else { return }
        onChange?()
    }

    private func beginScan(rootIDs: [UUID]?) {
        guard let database else { return }
        cancelScan()
        scanTask = Task { [weak self] in
            let roots = (try? LibraryRootStore(db: database).roots()) ?? []
            let scanner = WineupLibrary.Scanner(database: database)
            var changed = false
            for root in roots where rootIDs?.contains(root.id) ?? true {
                if Task.isCancelled { return }
                do {
                    for try await progress in scanner.scan(rootID: root.id) {
                        if progress.finished { changed = changed || progress.changed }
                        if progress.toRead > 0 { self?.onStatus?(String(localized: "Varrendo biblioteca: \(progress.read)/\(progress.toRead)")) }
                    }
                } catch {
                    changed = true   // varredura parcial: relê a lista por segurança
                    self?.onStatus?(String(localized: "Falha ao varrer uma pasta da biblioteca."))
                }
            }
            guard !Task.isCancelled else { return }
            // Nada mudou no disco: a lista fica como está (sem recarregar nem perder a seleção).
            if changed { await self?.reload() }
            self?.onStatus?(nil)
            self?.scanTask = nil
            if let self, self.hasPending {
                let pending = self.pendingRoots
                self.hasPending = false
                self.pendingRoots = nil
                self.beginScan(rootIDs: pending.map(Array.init))
            }
        }
    }
}
