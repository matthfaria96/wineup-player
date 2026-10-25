import AppKit
import SwiftUI
import WineupLibrary

/// Uma coluna da lista de Metadados: título, largura, ordenação e como desenhar a célula.
struct MetadataColumn {
    enum Content {
        /// Texto simples (rápido, NSTextField): valor, editado?, dica.
        case text((MetadataRow) -> (value: String, edited: Bool, tooltip: String?))
        /// Nome com capa, selos e confiança.
        case name
        /// Símbolo da letra.
        case lyrics
    }

    let id: String
    let title: String
    let minWidth: CGFloat
    let width: CGFloat
    let maxWidth: CGFloat
    var alignment: NSTextAlignment = .left
    var monospaced = false
    var truncatesHead = false
    var hideable = true
    /// Comparador da coluna (nil = não ordena por ela).
    let sort: ((SortOrder) -> KeyPathComparator<MetadataRow>)?
    let content: Content

    /// Colunas na ordem padrão (a mesma da tabela anterior; as extras começam escondidas).
    static let all: [MetadataColumn] = [
        MetadataColumn(id: "file", title: String(localized: "Nome do Arquivo"), minWidth: 160, width: 260, maxWidth: 2000,
                       hideable: false, sort: { KeyPathComparator(\.sortFile, order: $0) },
                       content: .name),
        MetadataColumn(id: "duration", title: String(localized: "Duração"), minWidth: 52, width: 52, maxWidth: 52,
                       alignment: .right, monospaced: true, sort: { KeyPathComparator(\.sortDuration, order: $0) },
                       content: .text { ($0.file.duration.map(LyricsBox.time) ?? "", false, nil) }),
        MetadataColumn(id: "lyrics", title: String(localized: "Letra"), minWidth: 38, width: 38, maxWidth: 38, sort: nil,
                       content: .lyrics),
        MetadataColumn(id: "path", title: String(localized: "Caminho"), minWidth: 80, width: 150, maxWidth: 2000,
                       truncatesHead: true, sort: { KeyPathComparator(\.sortPath, order: $0) },
                       content: .text { (NavPlaces.displayPath($0.url.deletingLastPathComponent()), false, $0.url.path) }),
        field("title", String(localized: "Título"), 80, 160, sort: { KeyPathComparator(\.sortTitle, order: $0) }),
        field("artist", String(localized: "Artista"), 70, 130, sort: { KeyPathComparator(\.sortArtist, order: $0) }),
        field("album", String(localized: "Álbum"), 70, 140, sort: { KeyPathComparator(\.sortAlbum, order: $0) }),
        field("year", String(localized: "Ano"), 44, 44, max: 44, mono: true, sort: { KeyPathComparator(\.sortYear, order: $0) }),
        field("track", String(localized: "Faixa"), 40, 40, max: 40, mono: true, right: true, key: "trackNumber",
              sort: { KeyPathComparator(\.sortTrack, order: $0) }),
        field("genre", String(localized: "Gênero"), 60, 110, sort: { KeyPathComparator(\.sortGenre, order: $0) }),
        field("albumArtist", String(localized: "Artista do Álbum"), 70, 130, sort: { KeyPathComparator(\.sortAlbumArtist, order: $0) }),
        field("disc", String(localized: "Disco"), 40, 40, max: 40, mono: true, key: "discNumber",
              sort: { KeyPathComparator(\.sortDisc, order: $0) }),
        field("comment", String(localized: "Comentário"), 60, 110, sort: { KeyPathComparator(\.sortComment, order: $0) }),
        field("composer", String(localized: "Compositor"), 60, 110, sort: { KeyPathComparator(\.sortComposer, order: $0) }),
        MetadataColumn(id: "tag", title: String(localized: "Etiqueta"), minWidth: 60, width: 90, maxWidth: 600,
                       sort: { KeyPathComparator(\.file.tech.tagFormat, order: $0) },
                       content: .text { ($0.file.tech.tagFormat, false, nil) }),
        MetadataColumn(id: "codec", title: String(localized: "Codec"), minWidth: 60, width: 110, maxWidth: 600,
                       sort: { KeyPathComparator(\.file.tech.codec, order: $0) },
                       content: .text { ($0.file.tech.codec, false, nil) }),
        MetadataColumn(id: "bitrate", title: String(localized: "Bitrate"), minWidth: 60, width: 76, maxWidth: 300,
                       alignment: .right, monospaced: true, sort: { KeyPathComparator(\.sortBitrate, order: $0) },
                       content: .text { ($0.file.tech.bitrateText, false, nil) }),
        MetadataColumn(id: "samplerate", title: String(localized: "Taxa de Amostragem"), minWidth: 60, width: 80, maxWidth: 300,
                       sort: { KeyPathComparator(\.sortSampleRate, order: $0) },
                       content: .text { ($0.file.tech.sampleRateText, false, nil) }),
        MetadataColumn(id: "size", title: String(localized: "Tamanho"), minWidth: 56, width: 66, maxWidth: 300,
                       alignment: .right, monospaced: true, sort: { KeyPathComparator(\.file.size, order: $0) },
                       content: .text { (ByteCountFormatter.string(fromByteCount: $0.file.size, countStyle: .file), false, nil) }),
    ]

    /// Campo de tag editável: valor atual (com a edição pendente) e destaque quando alterado.
    private static func field(_ id: String, _ title: String, _ min: CGFloat, _ width: CGFloat, max: CGFloat = 2000,
                              mono: Bool = false, right: Bool = false, key: String? = nil,
                              sort: @escaping (SortOrder) -> KeyPathComparator<MetadataRow>) -> MetadataColumn {
        let field = key ?? id
        return MetadataColumn(id: id, title: title, minWidth: min, width: width, maxWidth: max,
                              alignment: right ? .right : .left, monospaced: mono, sort: sort,
                              content: .text { ($0.value(field), $0.isEdited(field), nil) })
    }

    /// Coluna que ordena com o mesmo key path do comparador (para mostrar a seta no cabeçalho).
    static func column(for comparator: KeyPathComparator<MetadataRow>) -> MetadataColumn? {
        all.first { $0.sort?(.forward).keyPath == comparator.keyPath }
    }
}
