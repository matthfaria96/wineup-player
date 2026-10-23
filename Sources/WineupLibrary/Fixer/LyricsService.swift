import Foundation

/// Busca de letras em cadeia: fonte principal, reserva sem chave e, com token do usuário, Musixmatch.
/// Para a tela, é "o catálogo online" — a fonte de cada letra nunca é mostrada.
public struct LyricsService: Sendable {
    public static let musixmatchTokenKey = "lyrics.musixmatchToken"

    private let primary: LRCLibClient
    private let backup: NetEaseLyricsClient?
    private let musixmatch: MusixmatchClient?
    /// Letras desligadas nas Opções: nenhuma consulta.
    private var disabled = false

    public init(primary: LRCLibClient = LRCLibClient(), backup: NetEaseLyricsClient? = NetEaseLyricsClient(),
                musixmatch: MusixmatchClient? = nil) {
        self.primary = primary
        self.backup = backup
        self.musixmatch = musixmatch
    }

    /// Com o token do Musixmatch salvo nas preferências, se houver.
    public static func standard() -> LyricsService {
        let token = (UserDefaults.standard.string(forKey: musixmatchTokenKey) ?? "").trimmingCharacters(in: .whitespaces)
        var s = LyricsService(musixmatch: token.isEmpty ? nil : MusixmatchClient(token: token))
        s.disabled = !OnlineServices.isOn(.lyrics)
        return s
    }

    /// Primeira letra aceitável; uma fonte fora do ar não impede as outras.
    public func best(title: String, artist: String, album: String?, duration: Double?,
                     syncedOnly: Bool = false) async throws -> LyricsCandidate? {
        guard !disabled else { return nil }
        var lastError: Error?
        var plainFallback: LyricsCandidate?
        let steps: [@Sendable () async throws -> LyricsCandidate?] = [
            { try await primary.best(title: title, artist: artist, album: album, duration: duration, syncedOnly: syncedOnly) },
            { try await backup?.best(title: title, artist: artist, album: album, duration: duration, syncedOnly: syncedOnly) },
            { try await musixmatch?.best(title: title, artist: artist, album: album, duration: duration, syncedOnly: syncedOnly) },
        ]
        for step in steps {
            do {
                guard let found = try await step() else { continue }
                if found.isSynced { return found }
                plainFallback = plainFallback ?? found
            } catch {
                lastError = error
            }
        }
        if let plainFallback { return plainFallback }
        if let lastError, !(lastError is MusixmatchClient.Failure) { throw lastError }
        return nil
    }

    /// Opções para escolha manual: as da fonte principal e as da reserva, sincronizadas primeiro.
    public func search(title: String, artist: String, duration: Double?) async throws -> [LyricsCandidate] {
        guard !disabled else { return [] }
        async let main = (try? await primary.search(title: title, artist: artist, duration: duration)) ?? []
        async let more = (try? await backup?.search(title: title, artist: artist, duration: duration)) ?? []
        var list = await main + more
        if let m = try? await musixmatch?.best(title: title, artist: artist, album: nil, duration: duration) {
            list.insert(m, at: 0)
        }
        return list.enumerated().sorted { a, b in
            if a.element.isSynced != b.element.isSynced { return a.element.isSynced }
            return a.offset < b.offset
        }.map(\.element)
    }
}
