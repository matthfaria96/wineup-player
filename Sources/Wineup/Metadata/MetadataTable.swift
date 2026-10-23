import SwiftUI
import WineupLibrary

/// Lista de arquivos; valores alterados (ainda não gravados) aparecem em destaque.
struct MetadataTable: View {
    @ObservedObject var model: MetadataManagerModel
    let onPickMatch: (MetadataRow.ID) -> Void

    var body: some View {
        Table(model.visibleRows, selection: $model.selection) {
            TableColumn("") { row in StatusIcon(row: row) }
                .width(22)
            TableColumn("Arquivo") { row in
                Text(row.fileName).lineLimit(1).help(row.url.path)
            }
            .width(min: 120, ideal: 190)
            TableColumn("Título") { row in cell(row, "title") }
                .width(min: 80, ideal: 140)
            TableColumn("Artista") { row in cell(row, "artist") }
                .width(min: 70, ideal: 110)
            TableColumn("Álbum") { row in cell(row, "album") }
                .width(min: 70, ideal: 110)
            TableColumn("Faixa") { row in cell(row, "trackNumber").monospacedDigit() }
                .width(40)
            TableColumn("Ano") { row in cell(row, "year").monospacedDigit() }
                .width(44)
            TableColumn("Gênero") { row in cell(row, "genre") }
                .width(min: 50, ideal: 80)
            TableColumn("Capa · Letra") { row in
                HStack(spacing: 6) {
                    flag(row.willHaveCover, pending: row.cover != nil, symbol: "photo")
                    lyricsFlag(row)
                }
            }
            .width(72)
            TableColumn("Confiança") { row in ConfidenceBadge(row: row) }
                .width(min: 70, ideal: 90)
        }
        .contextMenu(forSelectionType: MetadataRow.ID.self) { ids in
            Button("Buscar dados") { model.selection = ids; model.autoFix(onlySelection: true) }
            if ids.count == 1, let id = ids.first {
                Button("Escolher resultado…") { onPickMatch(id) }
            }
            Button("Salvar") { model.selection = ids; model.save(onlySelection: true) }
            Button("Desfazer alterações") { model.selection = ids; model.revertSelection() }
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

    private func flag(_ has: Bool, pending: Bool, symbol: String) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(pending ? Color.accentColor : has ? Color.secondary : Color.red.opacity(0.75))
            .opacity(has ? 1 : 0.55)
            .help(pending ? "Será gravada" : has ? "Tem" : "Falta")
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
