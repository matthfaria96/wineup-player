import Foundation
import WineupLibrary

/// Uma linha do gerenciador: o arquivo como está no disco mais o que o usuário (ou a busca) quer mudar.
struct MetadataRow: Identifiable, Equatable {
    enum Status: Equatable {
        case idle, searching, review, ready, notFound, saved
        case failed(String)

        var label: String {
            switch self {
            case .idle: ""
            case .searching: "Buscando…"
            case .review: "Revisar"
            case .ready: "Pronta para salvar"
            case .notFound: "Não encontrada"
            case .saved: "Salva"
            case .failed(let m): m
            }
        }
    }

    /// Chaves pré-calculadas de ordenação e do filtro de texto; refeitas só quando o arquivo ou as edições mudam.
    struct Keys: Equatable {
        var search = ""
        var file = "", title = "", artist = "", album = "", genre = "", path = ""
        var albumArtist = "", comment = "", composer = ""
        var track = 0, year = 0, disc = 0
    }

    var file: FixerFile { didSet { refreshKeys() } }
    /// Campos (vocabulário do TagSnapshot) com valor novo; "" limpa o campo.
    var edits: [String: String] = [:] { didSet { refreshKeys() } }
    var cover: CoverImage?
    var lyrics: LyricsCandidate?
    var replaceLyrics = false
    var proposal: FixProposal?
    var status: Status = .idle
    /// Problemas que o usuário mandou ignorar neste arquivo (não contam e não voltam).
    var ignored: Set<FixerIssue> = []
    private(set) var keys = Keys()

    init(file: FixerFile, proposal: FixProposal? = nil, status: Status = .idle, ignored: Set<FixerIssue> = []) {
        self.file = file
        self.proposal = proposal
        self.status = status
        self.ignored = ignored
        refreshKeys()
    }

    var id: String { file.id }
    var url: URL { file.url }
    var fileName: String { file.url.lastPathComponent }
    var confidence: Double? { proposal?.match?.confidence }

    func value(_ field: String) -> String { edits[field] ?? file.value(field) }

    private mutating func refreshKeys() {
        let title = value("title"), artist = value("artist"), album = value("album")
        keys = Keys(
            search: ManagerSearch.key([fileName, title, artist, album]),
            file: fileName.lowercased(), title: title.lowercased(), artist: artist.lowercased(),
            album: album.lowercased(), genre: value("genre").lowercased(),
            path: url.deletingLastPathComponent().path.lowercased(),
            albumArtist: value("albumArtist").lowercased(), comment: value("comment").lowercased(),
            composer: value("composer").lowercased(),
            track: (Int(value("discNumber")) ?? 1) * 1000 + (Int(value("trackNumber")) ?? 999),
            year: Int(value("year").prefix(4)) ?? 0, disc: Int(value("discNumber")) ?? 0)
    }

    // Chaves de ordenação da tabela (faixa e ano como número), lidas do cache.
    var sortFile: String { keys.file }
    var sortTitle: String { keys.title }
    var sortArtist: String { keys.artist }
    var sortAlbum: String { keys.album }
    var sortGenre: String { keys.genre }
    var sortTrack: Int { keys.track }
    var sortYear: Int { keys.year }
    var sortConfidence: Double { confidence ?? -1 }
    var sortPath: String { keys.path }
    var sortAlbumArtist: String { keys.albumArtist }
    var sortComment: String { keys.comment }
    var sortComposer: String { keys.composer }
    var sortDisc: Int { keys.disc }
    var sortBitrate: Int { file.tech.bitrate ?? 0 }
    var sortSampleRate: Double { file.tech.sampleRate ?? 0 }
    var sortDuration: Double { file.duration ?? 0 }
    func isEdited(_ field: String) -> Bool { edits[field] != nil }

    var hasTagChanges: Bool { !edits.isEmpty || cover != nil }
    var isDirty: Bool { hasTagChanges || lyrics?.text != nil }

    /// Define um campo como digitado (o espaço no fim não some no meio da digitação);
    /// igual ao valor do arquivo desfaz a edição. O texto é aparado só ao gravar (`tagChanges`).
    mutating func set(_ field: String, _ value: String) {
        let stored = ManagerEdits.stored(value, original: file.value(field))
        guard edits[field] != stored else { return }
        edits[field] = stored
    }

    /// Status depois de uma edição: com alteração fica "Pronta para salvar"; sem, volta ao normal.
    mutating func refreshStatus() {
        if isDirty { status = .ready } else if status == .ready { status = .idle }
    }

    /// Letra nova (ou nil para descartar); substitui o .lrc existente ao salvar.
    mutating func setLyrics(_ new: LyricsCandidate?) {
        lyrics = new
        replaceLyrics = file.hasSidecarLyrics
        refreshStatus()
    }

    /// O que vai para o arquivo: valores aparados, sem os que ficaram iguais ao original.
    var tagChanges: TagChanges {
        TagChanges(fields: ManagerEdits.committed(edits, original: file.value), cover: cover)
    }

    var willHaveCover: Bool { cover != nil || file.hasCover }
    var willHaveLyrics: Bool { lyrics?.text != nil || file.hasLyrics }

    /// Itens essenciais de uma música "ok" que ainda faltam depois das alterações pendentes (nomes visíveis):
    /// título, artista, álbum, ano, faixa e gênero, mais capa e letra.
    /// Problema que o usuário mandou ignorar não conta como falta.
    var missingEssentials: [String] {
        let checks: [(String, Bool, FixerIssue)] = [
            ("Título", value("title").isEmpty, .missingTitle), ("Artista", value("artist").isEmpty, .missingArtist),
            ("Álbum", value("album").isEmpty, .missingAlbum), ("Ano", value("year").isEmpty, .missingYear),
            ("Faixa", value("trackNumber").isEmpty, .missingTrack), ("Gênero", value("genre").isEmpty, .missingGenre),
            ("Capa", !willHaveCover, .missingCover), ("Letra", !willHaveLyrics, .missingLyrics),
        ]
        return checks.filter { $0.1 && !ignored.contains($0.2) }.map(\.0)
    }

    /// Título, artista, álbum, ano, faixa, gênero, capa e letra preenchidos.
    var isComplete: Bool { missingEssentials.isEmpty }

    /// Itens que a busca trouxe e ainda não foram gravados (nomes visíveis).
    var foundItems: [String] {
        var out = edits.keys.sorted().map(MetadataFieldName.label)
        if cover != nil { out.append("Capa") }
        if lyrics?.text != nil { out.append("Letra") }
        return out
    }

    /// Problemas que continuam depois das alterações pendentes.
    var openIssues: [FixerIssue] {
        file.issues.subtracting(ignored).filter { issue in
            switch issue {
            case .missingTitle: value("title").isEmpty
            case .missingArtist: value("artist").isEmpty
            case .missingAlbum: value("album").isEmpty
            case .missingYear: value("year").isEmpty
            case .missingTrack: value("trackNumber").isEmpty
            case .missingGenre: value("genre").isEmpty
            case .missingCover: !willHaveCover
            case .missingLyrics: !willHaveLyrics
            case .duplicate: true
            }
        }.sorted { $0.rawValue < $1.rawValue }
    }
}

/// Filtro da lista.
enum MetadataFilter: String, CaseIterable, Identifiable {
    case all, problems, changed, duplicates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todas"
        case .problems: "Com problemas"
        case .changed: "Alteradas"
        case .duplicates: "Duplicadas"
        }
    }

    func includes(_ row: MetadataRow) -> Bool {
        switch self {
        case .all: true
        case .problems: !row.openIssues.isEmpty
        case .changed: row.isDirty
        case .duplicates: row.file.duplicateGroup != nil
        }
    }
}

/// Nome visível de cada campo editável.
enum MetadataFieldName {
    static func label(_ field: String) -> String {
        switch field {
        case "title": "Título"
        case "artist": "Artista"
        case "album": "Álbum"
        case "year": "Ano"
        case "trackNumber": "Faixa"
        case "genre": "Gênero"
        case "comment": "Comentário"
        case "albumArtist": "Artista do álbum"
        case "composer": "Compositor"
        case "discNumber": "Disco"
        default: field
        }
    }
}
