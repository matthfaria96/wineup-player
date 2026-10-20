import Foundation

/// Backups dos arquivos antes de qualquer gravação: clonefile (sem custo em APFS) com fallback de cópia.
public struct BackupStore: Sendable {
    public static let reserveBytes: Int64 = 50 * 1024 * 1024

    public let directory: URL
    private let clone: @Sendable (String, String) -> Int32
    private let availableBytes: @Sendable (URL) throws -> Int64

    public init(
        directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wineup/Backups", isDirectory: true),
        clone: @escaping @Sendable (String, String) -> Int32 = { clonefile($0, $1, 0) },
        availableBytes: @escaping @Sendable (URL) throws -> Int64 = BackupStore.systemAvailableBytes
    ) {
        self.directory = directory
        self.clone = clone
        self.availableBytes = availableBytes
    }

    public static let systemAvailableBytes: @Sendable (URL) throws -> Int64 = { url in
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }

    /// Cria `<directory>/<uuid>/<nome original>`.
    public func backup(_ src: URL, id: UUID) throws -> URL {
        let folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(src.lastPathComponent)
        do {
            try duplicate(src, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return dest
    }

    /// Remove o backup e a pasta do uuid.
    public func remove(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let folder = url.deletingLastPathComponent()
        if folder.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
            try? fm.removeItem(at: folder)
        }
    }

    /// Clona; se o volume não suporta (ENOTSUP/EXDEV), confere espaço e copia.
    func duplicate(_ src: URL, to dest: URL) throws {
        if clone(src.path, dest.path) == 0 { return }
        let code = errno
        guard code == ENOTSUP || code == EXDEV else { throw TagWriterError.writeFailed }
        let size = (try? FileStat.of(src).size) ?? 0
        let free = try availableBytes(dest.deletingLastPathComponent())
        guard free >= size + Self.reserveBytes else { throw TagWriterError.insufficientSpace }
        try FileManager.default.copyItem(at: src, to: dest)
    }
}
