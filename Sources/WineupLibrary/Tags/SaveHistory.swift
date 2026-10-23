import Foundation

/// Um "Salvar" do gerenciador de metadados: o que foi gravado em cada arquivo, para desfazer em lote.
public struct SaveBatch: Codable, Identifiable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable {
        public var path: String
        /// Entrada do diário do TagWriter (tags/capa), se houve.
        public var journalID: UUID?
        /// Cópia do .lrc que existia antes (nil = não havia .lrc).
        public var lyricsBackup: String?
        /// O .lrc foi criado ou trocado nesta gravação.
        public var wroteLyrics: Bool

        public init(path: String, journalID: UUID? = nil, lyricsBackup: String? = nil, wroteLyrics: Bool = false) {
            self.path = path; self.journalID = journalID; self.lyricsBackup = lyricsBackup; self.wroteLyrics = wroteLyrics
        }

        public var lyricsURL: URL { URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("lrc") }
    }

    public let id: UUID
    public let date: Date
    public let folder: String
    public var items: [Item]
    public var undone: Bool

    public init(id: UUID = UUID(), date: Date = Date(), folder: String, items: [Item], undone: Bool = false) {
        self.id = id; self.date = date; self.folder = folder; self.items = items; self.undone = undone
    }
}

/// Histórico de gravações (JSON em Application Support), mais recente primeiro.
public final class SaveHistoryStore: @unchecked Sendable {
    public static let shared = SaveHistoryStore()

    private let url: URL
    private let lyricsBackups: URL
    private let lock = NSLock()

    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Wineup", isDirectory: true)) {
        url = directory.appendingPathComponent("metadata-history.json")
        lyricsBackups = directory.appendingPathComponent("Backups/lyrics", isDirectory: true)
    }

    public func batches() -> [SaveBatch] {
        lock.withLock {
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([SaveBatch].self, from: data)) ?? []
        }
    }

    public func add(_ batch: SaveBatch) throws {
        try update { list in list.insert(batch, at: 0); list = Array(list.prefix(200)) }
    }

    public func markUndone(_ id: UUID) throws {
        try update { list in if let i = list.firstIndex(where: { $0.id == id }) { list[i].undone = true } }
    }

    private func update(_ change: (inout [SaveBatch]) -> Void) throws {
        try lock.withLock {
            var list = ((try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([SaveBatch].self, from: $0) }) ?? []
            change(&list)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(list).write(to: url, options: .atomic)
        }
    }

    /// Guarda uma cópia do .lrc atual antes de trocá-lo; devolve o caminho da cópia (nil se não havia).
    public func backupLyrics(of lrc: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: lrc.path) else { return nil }
        try FileManager.default.createDirectory(at: lyricsBackups, withIntermediateDirectories: true)
        let dest = lyricsBackups.appendingPathComponent("\(UUID().uuidString)-\(lrc.lastPathComponent)")
        try FileManager.default.copyItem(at: lrc, to: dest)
        return dest.path
    }
}

/// Desfaz um lote: tags e capa pelo diário (com verificação de que o arquivo não mudou depois),
/// e o .lrc volta ao que era (ou vai para a Lixeira, se foi criado nesta gravação).
public enum BatchUndo {
    public struct Result: Sendable, Equatable {
        public var restored: Int
        public var failed: [String]
    }

    public static func undo(_ batch: SaveBatch, writer: TagWriter,
                            remove: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> Result {
        var result = Result(restored: 0, failed: [])
        for item in batch.items {
            do {
                if let id = item.journalID { try writer.undo(entryID: id) }
                if item.wroteLyrics {
                    let lrc = item.lyricsURL
                    if let backup = item.lyricsBackup {
                        _ = try FileManager.default.replaceItemAt(lrc, withItemAt: copyForRestore(backup))
                    } else if FileManager.default.fileExists(atPath: lrc.path) {
                        try remove(lrc)
                    }
                }
                result.restored += 1
            } catch {
                result.failed.append(URL(fileURLWithPath: item.path).lastPathComponent)
            }
        }
        return result
    }

    /// replaceItemAt consome o arquivo de origem: restaura a partir de uma cópia, o backup fica.
    private static func copyForRestore(_ backup: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".lrc")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: backup), to: tmp)
        return tmp
    }
}
