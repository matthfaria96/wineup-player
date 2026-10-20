import Foundation
import GRDB
import WineupCore

/// Regra NAV-01: na primeira abertura, a pasta Música do usuário vira raiz da biblioteca.
public enum LibraryBootstrap {
    static let flagKey = "default_root_bootstrapped"

    /// Devolve a raiz criada, ou nil quando não se aplica (já rodou, já há raízes, pasta ausente).
    /// Nunca lança por causa da pasta padrão: o app deve abrir normalmente.
    @discardableResult
    public static func ensureDefaultRoot(
        database: LibraryDatabase,
        musicDirectory: URL? = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
    ) throws -> LibraryRoot? {
        let alreadyDone = try database.pool.write { d -> Bool in
            let flag = try String.fetchOne(d, sql: "SELECT value FROM app_setting WHERE key = ?",
                                           arguments: [flagKey])
            if flag != nil { return true }
            try d.execute(sql: "INSERT INTO app_setting (key, value) VALUES (?, '1')", arguments: [flagKey])
            return false
        }
        if alreadyDone { return nil }

        let store = LibraryRootStore(db: database)
        guard try store.roots().isEmpty else { return nil }
        guard let musicDirectory else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: musicDirectory.path, isDirectory: &isDir),
              isDir.boolValue,
              FileManager.default.isReadableFile(atPath: musicDirectory.path) else { return nil }
        return try? store.addRoot(musicDirectory)
    }
}
