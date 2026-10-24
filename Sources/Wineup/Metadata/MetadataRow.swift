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

    var file: FixerFile
    /// Campos (vocabulário do TagSnapshot) com valor novo; "" limpa o campo.
    var edits: [String: String] = [:]
    var cover: CoverImage?
    var lyrics: LyricsCandidate?
    var replaceLyrics = false
    var proposal: FixProposal?
    var status: Status = .idle
    /// Problemas que o usuário mandou ignorar neste arquivo (não contam e não voltam).
    var ignored: Set<FixerIssue> = []

    var id: String { file.id }
    var url: URL { file.url }
    var fileName: String { file.url.lastPathComponent }
    var confidence: Double? { proposal?.match?.confidence }

    func value(_ field: String) -> String { edits[field] ?? file.value(field) }

    // Chaves de ordenação da tabela (faixa e ano como número).
    var sortFile: String { fileName.lowercased() }
    var sortTitle: String { value("title").lowercased() }
    var sortArtist: String { value("artist").lowercased() }
    var sortAlbum: String { value("album").lowercased() }
    var sortGenre: String { value("genre").lowercased() }
    var sortTrack: Int { (Int(value("discNumber")) ?? 1) * 1000 + (Int(value("trackNumber")) ?? 999) }
    var sortYear: Int { Int(value("year").prefix(4)) ?? 0 }
    var sortConfidence: Double { confidence ?? -1 }
    var sortPath: String { url.deletingLastPathComponent().path.lowercased() }
    var sortAlbumArtist: String { value("albumArtist").lowercased() }
    var sortComment: String { value("comment").lowercased() }
    var sortComposer: String { value("composer").lowercased() }
    var sortDisc: Int { Int(value("discNumber")) ?? 0 }
    var sortBitrate: Int { file.tech.bitrate ?? 0 }
    var sortSampleRate: Double { file.tech.sampleRate ?? 0 }
    var sortDuration: Double { file.duration ?? 0 }
    func isEdited(_ field: String) -> Bool { edits[field] != nil }

    var hasTagChanges: Bool { !edits.isEmpty || cover != nil }
    var isDirty: Bool { hasTagChanges || lyrics?.text != nil }

    /// Define um campo; voltar ao valor do arquivo desfaz a edição.
    mutating func set(_ field: String, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed == file.value(field) { edits[field] = nil } else { edits[field] = trimmed }
    }

    var tagChanges: TagChanges { TagChanges(fields: edits, cover: cover) }

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
