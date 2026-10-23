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
                TableColumn("", value: \.sortConfidence) { row in RowThumb(row: row) }
                    .width(26)
                    .customizationID("thumb")
                    .disabledCustomizationBehavior(.all)
                TableColumn("Nome do Arquivo", value: \.sortFile) { row in
                    Text(row.fileName).lineLimit(1).help(row.url.path)
                }
                .width(min: 120, ideal: 210)
                .customizationID("file")
                TableColumn("Caminho", value: \.sortPath) { row in
                    Text(row.url.deletingLastPathComponent().path).lineLimit(1).truncationMode(.head).help(row.url.path)
                }
                .width(min: 80, ideal: 150)
                .customizationID("path")
                TableColumn("Etiqueta", value: \.file.tech.tagFormat) { row in Text(row.file.tech.tagFormat).lineLimit(1) }
                    .width(min: 60, ideal: 90)
                    .customizationID("tag")
                TableColumn("Título", value: \.sortTitle) { row in cell(row, "title") }
                    .width(min: 80, ideal: 160)
                    .customizationID("title")
                TableColumn("Faixa", value: \.sortTrack) { row in cell(row, "trackNumber").monospacedDigit() }
                    .width(40)
                    .alignment(.trailing)
                    .customizationID("track")
                TableColumn("Artista", value: \.sortArtist) { row in cell(row, "artist") }
                    .width(min: 70, ideal: 130)
                    .customizationID("artist")
                TableColumn("Artista do Álbum", value: \.sortAlbumArtist) { row in cell(row, "albumArtist") }
                    .width(min: 70, ideal: 130)
                    .customizationID("albumArtist")
                TableColumn("Álbum", value: \.sortAlbum) { row in cell(row, "album") }
                    .width(min: 70, ideal: 140)
                    .customizationID("album")
                TableColumn("Disco", value: \.sortDisc) { row in cell(row, "discNumber").monospacedDigit() }
                    .width(40)
                    .customizationID("disc")
            }
            Group {
                TableColumn("Ano", value: \.sortYear) { row in cell(row, "year").monospacedDigit() }
                    .width(44)
                    .customizationID("year")
                TableColumn("Gênero", value: \.sortGenre) { row in cell(row, "genre") }
                    .width(min: 60, ideal: 110)
                    .customizationID("genre")
                TableColumn("Comentário", value: \.sortComment) { row in cell(row, "comment") }
                    .width(min: 60, ideal: 110)
                    .customizationID("comment")
                TableColumn("Compositor", value: \.sortComposer) { row in cell(row, "composer") }
                    .width(min: 60, ideal: 110)
                    .customizationID("composer")
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
                TableColumn("Duração", value: \.sortDuration) { row in
                    Text(row.file.duration.map(LyricsBox.time) ?? "").monospacedDigit()
                }
                .width(52)
                .alignment(.trailing)
                .customizationID("duration")
                TableColumn("Tamanho", value: \.file.size) { row in
                    Text(ByteCountFormatter.string(fromByteCount: row.file.size, countStyle: .file)).monospacedDigit()
                }
                .width(min: 56, ideal: 66)
                .alignment(.trailing)
                .customizationID("size")
                TableColumn("Letra") { row in lyricsFlag(row) }
                    .width(38)
                    .customizationID("lyrics")
            }
            TableColumn("Confiança", value: \.sortConfidence) { row in ConfidenceBadge(row: row) }
                .width(min: 70, ideal: 90)
                .customizationID("confidence")
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
            if model.rows.contains(where: { ids.contains($0.id) && !$0.ignored.isEmpty }) {
                Button("Voltar a mostrar problemas ignorados") { model.unignore(ids: ids) }
            }
            Divider()
            Button("Mostrar no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(model.rows.filter { ids.contains($0.id) }.map(\.url))
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

    /// Relógio verde = letra sincronizada; texto laranja = estática; apagado = sem letra.
    private func lyricsFlag(_ row: MetadataRow) -> some View {
        let synced = row.lyrics.map(\.isSynced) ?? row.file.lyricsSynced
        let pending = row.lyrics?.text != nil
        return Image(systemName: synced == true ? "clock.fill" : synced == false ? "text.alignleft" : "text.quote")
            .foregroundStyle(pending ? Color.accentColor : synced == true ? .green : synced == false ? .orange : Color.red.opacity(0.75))
            .opacity(synced == nil ? 0.55 : 1)
            .help(synced == nil ? "Sem letra" : (synced! ? "Letra sincronizada" : "Letra estática (sem tempo)") + (pending ? " · será gravada" : ""))
    }

}

/// Ícone do estado da linha (problemas, buscando, pronta, salva, erro).
struct StatusIcon: View {
    let row: MetadataRow

    var body: some View {
        Group {
            switch row.status {
            case .searching: ProgressView().controlSize(.mini)
            case .saved: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .ready: Image(systemName: "pencil.circle.fill").foregroundStyle(Color.accentColor)
            case .review: Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
            case .notFound: Image(systemName: "minus.circle").foregroundStyle(.secondary)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .idle:
                if row.openIssues.isEmpty { Image(systemName: "circle").foregroundStyle(.tertiary) }
                else { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
            }
        }
        .help(tooltip)
    }

    private var tooltip: String {
        let issues = row.openIssues.map(\.label).joined(separator: ", ")
        return [row.status.label, issues].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Confiança da correspondência (verde ≥ 80 %, laranja abaixo).
struct ConfidenceBadge: View {
    let row: MetadataRow

    var body: some View {
        if let c = row.confidence {
            HStack(spacing: 4) {
                Capsule().fill(color(c)).frame(width: 30 * c + 4, height: 5)
                Text("\(Int((c * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
            }
            .help(row.proposal?.match.map { "\($0.source.rawValue): \($0.title) · \($0.artist) · \($0.album ?? "sem álbum")" } ?? "")
        } else if case .failed(let m) = row.status {
            Text(m).foregroundStyle(.red).lineLimit(1).help(m)
        } else if row.status == .notFound {
            Text("Não encontrada").foregroundStyle(.secondary)
        }
    }

    private func color(_ c: Double) -> Color {
        c >= MetadataFixer.autoApplyConfidence ? .green : c >= 0.6 ? .orange : .red
    }
}

/// Miniatura da capa da linha com o estado num selo no canto (como as miniaturas do Mp3tag,
/// mais o selo: alteração pendente, salva, revisar, problema, erro).
struct RowThumb: View {
    let row: MetadataRow
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.medium).scaledToFill()
                } else {
                    Image(systemName: "music.note").font(.system(size: 9)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.15))
                }
            }
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            StatusBadge(row: row).offset(x: 4, y: 3)
        }
        .frame(width: 20, height: 17)
        .help(StatusBadge.tooltip(row))
        .task(id: "\(row.id)|\(row.cover?.data.count ?? -1)|\(row.file.coverBytes)") {
            image = await ThumbnailCache.shared.thumbnail(for: row)
        }
    }
}

/// Selo de estado (pequeno, sobre a miniatura). Sem selo = nada a fazer.
struct StatusBadge: View {
    let row: MetadataRow

    var body: some View {
        switch row.status {
        case .searching: ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 10, height: 10)
        case .saved: badge("checkmark", .green)
        case .ready: badge("pencil", .accentColor)
        case .review: badge("questionmark", .orange)
        case .notFound: badge("minus", .gray)
        case .failed: badge("xmark", .red)
        case .idle:
            if !row.openIssues.isEmpty { badge("exclamationmark", .orange) }
        }
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 6, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 10, height: 10)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
    }

    static func tooltip(_ row: MetadataRow) -> String {
        let issues = row.openIssues.map(\.label).joined(separator: ", ")
        return [row.status.label, issues].filter { !$0.isEmpty }.joined(separator: " · ")
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
