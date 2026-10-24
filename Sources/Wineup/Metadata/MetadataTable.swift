import SwiftUI
import WineupLibrary

/// Lista de arquivos; valores alterados (ainda não gravados) aparecem em destaque.
struct MetadataTable: View {
    @ObservedObject var model: MetadataManagerModel
    let onPickMatch: (MetadataRow.ID) -> Void

    var body: some View {
        // Uma única avaliação de filtro/ordenação por desenho.
        let visible = model.visibleRows
        Table(visible, selection: $model.selection, sortOrder: $model.sortOrder,
              columnCustomization: $model.columnCustomization) {
            Group {
                // Nome com a capa, o selo de estado, a bolinha de "dados encontrados" e a confiança da busca.
                TableColumn("Nome do Arquivo", value: \.sortFile) { row in NameCell(row: row) }
                    .width(min: 160, ideal: 260)
                    .customizationID("file")
                    .disabledCustomizationBehavior(.visibility)
                TableColumn("Duração", value: \.sortDuration) { row in
                    Text(row.file.duration.map(LyricsBox.time) ?? "").monospacedDigit()
                }
                .width(52)
                .alignment(.trailing)
                .customizationID("duration")
                TableColumn("Letra") { row in lyricsFlag(row) }
                    .width(38)
                    .customizationID("lyrics")
                TableColumn("Caminho", value: \.sortPath) { row in
                    Text(row.url.deletingLastPathComponent().path).lineLimit(1).truncationMode(.head).help(row.url.path)
                }
                .width(min: 80, ideal: 150)
                .customizationID("path")
                TableColumn("Título", value: \.sortTitle) { row in cell(row, "title") }
                    .width(min: 80, ideal: 160)
                    .customizationID("title")
                TableColumn("Artista", value: \.sortArtist) { row in cell(row, "artist") }
                    .width(min: 70, ideal: 130)
                    .customizationID("artist")
                TableColumn("Álbum", value: \.sortAlbum) { row in cell(row, "album") }
                    .width(min: 70, ideal: 140)
                    .customizationID("album")
                TableColumn("Ano", value: \.sortYear) { row in cell(row, "year").monospacedDigit() }
                    .width(44)
                    .customizationID("year")
                TableColumn("Faixa", value: \.sortTrack) { row in cell(row, "trackNumber").monospacedDigit() }
                    .width(40)
                    .alignment(.trailing)
                    .customizationID("track")
                TableColumn("Gênero", value: \.sortGenre) { row in cell(row, "genre") }
                    .width(min: 60, ideal: 110)
                    .customizationID("genre")
            }
            Group {
                TableColumn("Artista do Álbum", value: \.sortAlbumArtist) { row in cell(row, "albumArtist") }
                    .width(min: 70, ideal: 130)
                    .customizationID("albumArtist")
                TableColumn("Disco", value: \.sortDisc) { row in cell(row, "discNumber").monospacedDigit() }
                    .width(40)
                    .customizationID("disc")
                TableColumn("Comentário", value: \.sortComment) { row in cell(row, "comment") }
                    .width(min: 60, ideal: 110)
                    .customizationID("comment")
                TableColumn("Compositor", value: \.sortComposer) { row in cell(row, "composer") }
                    .width(min: 60, ideal: 110)
                    .customizationID("composer")
                TableColumn("Etiqueta", value: \.file.tech.tagFormat) { row in Text(row.file.tech.tagFormat).lineLimit(1) }
                    .width(min: 60, ideal: 90)
                    .customizationID("tag")
                TableColumn("Codec", value: \.file.tech.codec) { row in Text(row.file.tech.codec).lineLimit(1) }
                    .width(min: 60, ideal: 110)
                    .customizationID("codec")
                TableColumn("Bitrate", value: \.sortBitrate) { row in Text(row.file.tech.bitrateText).monospacedDigit() }
                    .width(min: 60, ideal: 76)
                    .alignment(.trailing)
                    .customizationID("bitrate")
                TableColumn("Taxa de Amostragem", value: \.sortSampleRate) { row in Text(row.file.tech.sampleRateText) }
                    .width(min: 60, ideal: 80)
                    .customizationID("samplerate")
                TableColumn("Tamanho", value: \.file.size) { row in
                    Text(ByteCountFormatter.string(fromByteCount: row.file.size, countStyle: .file)).monospacedDigit()
                }
                .width(min: 56, ideal: 66)
                .alignment(.trailing)
                .customizationID("size")
            }
        }
        .font(.system(size: 11))
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: MetadataRow.ID.self) { ids in
            Button("Buscar dados") { model.selection = ids; model.autoFix(onlySelection: true) }
            if ids.count == 1, let id = ids.first {
                Button("Escolher resultado…") { onPickMatch(id) }
            }
            Button("Salvar") { model.selection = ids; model.save(onlySelection: true) }
            Button("Desfazer alterações") { model.selection = ids; model.revertSelection() }
            Divider()
            Menu("Ignorar problema") {
                Button("Todos os problemas desta seleção") { model.ignore(nil, ids: ids) }
                Divider()
                ForEach(FixerIssue.allCases, id: \.self) { issue in
                    Button(issue.label) { model.ignore(issue, ids: ids) }
                }
            }
            if model.positions(of: ids).contains(where: { !model.rows[$0].ignored.isEmpty }) {
                Button("Voltar a mostrar problemas ignorados") { model.unignore(ids: ids) }
            }
            Divider()
            Button("Mostrar no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(model.positions(of: ids).map { model.rows[$0].url })
            }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first { onPickMatch(id) }
        }
        .overlay {
            if model.rows.isEmpty && !model.isLoading {
                ContentUnavailableView("Nenhuma música", systemImage: "music.note",
                                       description: Text("Escolha uma pasta com músicas no botão Pasta."))
            }
        }
    }

    private func cell(_ row: MetadataRow, _ field: String) -> Text {
        let value = row.value(field)
        let edited = row.isEdited(field)
        return Text(value)
            .foregroundColor(edited ? .accentColor : .primary)
            .fontWeight(edited ? .semibold : .regular)
    }

    /// Letra: relógio verde = sincronizada; texto laranja = estática; traço vermelho = sem letra.
    /// Azul = letra nova, ainda não gravada. Passar o mouse explica.
    private func lyricsFlag(_ row: MetadataRow) -> some View {
        LyricsFlag(row: row)
    }
}

/// Miniaturas pequenas das capas (embutida ou pendente), em memória.
actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func thumbnail(for row: MetadataRow) async -> NSImage? {
        let key = "\(row.id)|\(row.cover?.data.count ?? -1)|\(row.file.coverBytes)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let data: Data?
        if let pending = row.cover { data = pending.data }
        else if row.file.hasCover {
            let url = row.url
            data = await Task.detached(priority: .utility) { FolderAnalyzer.embeddedCover(url) }.value
        } else { data = nil }
        guard let data, let image = Self.downsample(data, to: 40) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func downsample(_ data: Data, to pixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
