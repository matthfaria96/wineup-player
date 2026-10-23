import Foundation

/// O que a busca encontrou para um arquivo.
public struct FixProposal: Sendable, Equatable {
    public var match: MatchCandidate?
    public var candidates: [MatchCandidate]
    public var cover: CoverImage?
    public var lyrics: LyricsCandidate?

    public init(match: MatchCandidate? = nil, candidates: [MatchCandidate] = [],
                cover: CoverImage? = nil, lyrics: LyricsCandidate? = nil) {
        self.match = match; self.candidates = candidates; self.cover = cover; self.lyrics = lyrics
    }
}

/// Como usar o resultado: só preencher o que falta, ou também trocar o que já existe.
public enum FillPolicy: String, Sendable, CaseIterable {
    case missingOnly, overwrite
}

/// Junta MusicBrainz (+ AcoustID), Cover Art Archive e LRCLIB para um arquivo.
public struct MetadataFixer: Sendable {
    /// Abaixo disso a correspondência não é aplicada sozinha (vai para revisão).
    public static let autoApplyConfidence = 0.8

    private let musicBrainz: MusicBrainzClient
    private let covers: CoverArtClient
    private let lyrics: LRCLibClient
    private let acoustID: AcoustIDClient?
    private let fpcalc: String?
    private let hints: ITunesHintClient?
    private let shazam: ShazamRecognizer?

    public init(musicBrainz: MusicBrainzClient = MusicBrainzClient(), covers: CoverArtClient = CoverArtClient(),
                lyrics: LRCLibClient = LRCLibClient(), acoustID: AcoustIDClient? = nil,
                fpcalc: String? = AcoustIDClient.fpcalcPath(), hints: ITunesHintClient? = ITunesHintClient(),
                shazam: ShazamRecognizer? = nil) {
        self.musicBrainz = musicBrainz; self.covers = covers; self.lyrics = lyrics
        self.acoustID = acoustID; self.fpcalc = fpcalc; self.hints = hints; self.shazam = shazam
    }

    public var canFingerprint: Bool { acoustID != nil && fpcalc != nil }
    public var canRecognize: Bool { shazam != nil || canFingerprint }

    /// O que se sabe para a busca: tags; o que faltar vem do nome do arquivo.
    public static func query(for file: FixerFile) -> (title: String, artist: String, album: String?) {
        let guess = FilenameGuess.parse(file.url)
        let title = file.value("title").isEmpty ? guess.title : file.value("title")
        let artist = file.value("artist").isEmpty ? (guess.artist ?? "") : file.value("artist")
        let album = file.value("album")
        return (title, artist, album.isEmpty ? nil : album)
    }

    public func findMatches(for file: FixerFile) async throws -> [MatchCandidate] {
        let q = Self.query(for: file)
        var list = q.title.isEmpty ? [] : try await textMatches(title: q.title, artist: q.artist, album: q.album,
                                                                duration: file.duration)
        // Nome/título não bastou: reconhecer pelo som (Shazam, depois AcoustID).
        if (list.first?.confidence ?? 0) < Self.autoApplyConfidence {
            if let heard = try await shazamMatch(file) {
                list.removeAll { $0.id == heard.id }
                list.insert(heard, at: 0)
            } else if let byPrint = try await fingerprintMatch(file) {
                list.insert(byPrint, at: 0)
            }
        }
        return list
    }

    private func textMatches(title: String, artist: String, album: String?, duration: Double?) async throws -> [MatchCandidate] {
        var list: [MatchCandidate] = []
        var genre: String?
        // Sem álbum no arquivo: a dica do iTunes leva à versão de estúdio no MusicBrainz.
        if album == nil, let hint = try? await hints?.albumHint(title: title, artist: artist, duration: duration) {
            genre = hint.genre
            list = (try? await musicBrainz.search(title: title, artist: artist, album: hint.album, duration: duration)) ?? []
            list = list.filter { TextMatch.similarity($0.album ?? "", hint.album) > 0.8 }
        }
        let general = try await musicBrainz.search(title: title, artist: artist, album: album, duration: duration)
        list += general.filter { g in !list.contains { $0.id == g.id } }
        if let genre { for i in list.indices where list[i].genre == nil { list[i].genre = genre } }
        return list
    }

    /// O Shazam diz título e artista; o resto (álbum, ano, faixa, capa) vem do MusicBrainz.
    private func shazamMatch(_ file: FixerFile) async throws -> MatchCandidate? {
        guard let shazam, let heard = try? await shazam.recognize(file.url) else { return nil }
        let found = try await textMatches(title: heard.title, artist: heard.artist, album: nil, duration: file.duration)
        var best = found.first ?? MatchCandidate(source: .shazam, recordingID: "shazam:\(heard.isrc ?? heard.title)",
                                                 title: heard.title, artist: heard.artist)
        best.source = .shazam
        best.confidence = max(best.confidence, 0.9)
        return best
    }

    private func fingerprintMatch(_ file: FixerFile) async throws -> MatchCandidate? {
        guard let acoustID, let fpcalc, let fp = try AcoustIDClient.fingerprint(file.url, fpcalc: fpcalc),
              let best = try await acoustID.lookup(fp).first, best.score >= 0.5 else { return nil }
        var c = try await musicBrainz.recording(id: best.recordingID, preferAlbum: Self.query(for: file).album)
        c?.confidence = best.score
        return c
    }

    /// Busca completa: metadados, capa (se faltar ou `wantCover`) e letra (se faltar).
    public func propose(for file: FixerFile, wantCover: Bool? = nil, wantLyrics: Bool? = nil) async throws -> FixProposal {
        let candidates = try await findMatches(for: file)
        let match = candidates.first
        let q = Self.query(for: file)
        let title = match?.title ?? q.title, artist = match?.artist ?? q.artist
        // Letra estática também conta como "falta": busca a sincronizada.
        let staticOnly = file.hasLyrics && file.lyricsSynced == false
        let needCover = wantCover ?? !file.hasCover
        let needLyrics = (wantLyrics ?? (!file.hasLyrics || staticOnly)) && !title.isEmpty
        // Capa e letra vêm de serviços diferentes: em paralelo.
        async let cover: CoverImage? = needCover && match != nil
            ? (try? await covers.frontCover(releaseID: match?.releaseID, releaseGroupID: match?.releaseGroupID)) : nil
        async let words: LyricsCandidate? = needLyrics
            ? (try? await lyrics.best(title: title, artist: artist, album: match?.album ?? q.album,
                                      duration: file.duration, syncedOnly: staticOnly)) : nil
        return FixProposal(match: match, candidates: candidates, cover: await cover, lyrics: await words)
    }

    public func cover(for match: MatchCandidate) async throws -> CoverImage? {
        try await covers.frontCover(releaseID: match.releaseID, releaseGroupID: match.releaseGroupID)
    }

    public func lyricsOptions(for file: FixerFile, match: MatchCandidate?) async throws -> [LyricsCandidate] {
        let q = Self.query(for: file)
        return try await lyrics.search(title: match?.title ?? q.title, artist: match?.artist ?? q.artist,
                                       duration: file.duration)
    }

    /// Campos (vocabulário do TagSnapshot) que a correspondência mudaria no arquivo.
    public static func fieldChanges(_ match: MatchCandidate, file: FixerFile, policy: FillPolicy) -> [String: String] {
        match.fields.filter { field, value in
            let current = file.value(field)
            switch policy {
            case .missingOnly: return current.isEmpty
            case .overwrite: return current != value
            }
        }
    }
}

extension TagChanges {
    /// Monta as alterações a partir de campos no vocabulário do TagSnapshot.
    public init(fields: [String: String], cover: CoverImage? = nil) {
        self.init(title: fields["title"], artist: fields["artist"], album: fields["album"],
                  albumArtist: fields["albumArtist"], genre: fields["genre"], year: fields["year"],
                  trackNumber: fields["trackNumber"].flatMap { Int($0) },
                  discNumber: fields["discNumber"].flatMap { Int($0) },
                  composer: fields["composer"], comment: fields["comment"], cover: cover)
    }

    /// Campos editáveis no gerenciador, na ordem da barra lateral.
    public static let editableFields = ["title", "artist", "album", "year", "trackNumber", "genre",
                                        "comment", "albumArtist", "composer", "discNumber"]
}

/// Grava a letra ao lado da música (.lrc com o mesmo nome), de forma atômica.
public enum LyricsFileWriter {
    public enum WriteError: Error, Equatable { case alreadyExists, empty }

    public static func write(_ text: String, for audio: URL, replace: Bool) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WriteError.empty }
        let dest = audio.deletingPathExtension().appendingPathExtension("lrc")
        if !replace, FileManager.default.fileExists(atPath: dest.path) { throw WriteError.alreadyExists }
        try Data((trimmed + "\n").utf8).write(to: dest, options: .atomic)
        return dest
    }
}
