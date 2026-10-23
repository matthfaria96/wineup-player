import Foundation

/// Capas do Cover Art Archive (lançamento; senão o grupo de lançamento).
public struct CoverArtClient: Sendable {
    private let fetcher: HTTPFetching

    public init(fetcher: HTTPFetching = URLSessionFetcher()) { self.fetcher = fetcher }

    /// JPEG/PNG da capa frontal (500 px) ou nil se não existe.
    public func frontCover(releaseID: String?, releaseGroupID: String?) async throws -> CoverImage? {
        let paths = [releaseID.map { "release/\($0)" }, releaseGroupID.map { "release-group/\($0)" }].compactMap { $0 }
        for path in paths {
            guard let url = URL(string: "https://coverartarchive.org/\(path)/front-500") else { continue }
            let (data, status) = try await fetcher.get(url, headers: ["User-Agent": FixerHTTP.userAgent])
            if status == 404 { continue }
            guard (200..<300).contains(status), let mime = Self.mimeType(of: data) else { continue }
            return CoverImage(data: data, mimeType: mime)
        }
        return nil
    }

    /// Confere pelos bytes iniciais; nada que não seja JPEG/PNG vai para o arquivo.
    public static func mimeType(of data: Data) -> String? {
        let head = [UInt8](data.prefix(8))
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        return nil
    }
}
