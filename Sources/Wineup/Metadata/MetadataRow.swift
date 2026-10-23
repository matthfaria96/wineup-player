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

    var id: String { file.id }
    var url: URL { file.url }
    var fileName: String { file.url.lastPathComponent }
    var confidence: Double? { proposal?.match?.confidence }

    func value(_ field: String) -> String { edits[field] ?? file.value(field) }
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

    /// Problemas que continuam depois das alterações pendentes.
    var openIssues: [FixerIssue] {
        file.issues.filter { issue in
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
