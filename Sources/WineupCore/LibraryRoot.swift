import Foundation

/// Ponto único de acesso a pastas da biblioteca. O app roda sem sandbox.
public struct LibraryRoot: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let url: URL

    public init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }

    /// Compara caminhos padronizados com prefixo terminado em "/" (evita /Musica casar com /Music).
    public func contains(_ fileURL: URL) -> Bool {
        let root = url.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return fileURL.standardizedFileURL.path.hasPrefix(prefix)
    }
}
