import SwiftUI
import WineupLibrary

/// Escolha manual entre os resultados das bases (com a confiança de cada um).
struct MatchPicker: View {
    @ObservedObject var model: MetadataManagerModel
    let rowID: MetadataRow.ID
    @Environment(\.dismiss) private var dismiss
    @State private var choice: MatchCandidate.ID?

    private var row: MetadataRow? { model.rows.first { $0.id == rowID } }
    private var candidates: [MatchCandidate] { row?.proposal?.candidates ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resultados para \(row?.fileName ?? "")").font(.headline).lineLimit(1)
            if let row {
                let q = MetadataFixer.query(for: row.file)
                Text("Busca: \(q.title)\(q.artist.isEmpty ? "" : " · \(q.artist)")\(q.album.map { " · \($0)" } ?? "")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Table(candidates, selection: $choice) {
                TableColumn("Confiança") { c in
                    Text("\(Int((c.confidence * 100).rounded()))%").monospacedDigit()
                        .foregroundStyle(c.confidence >= MetadataFixer.autoApplyConfidence ? .green : .orange)
                }
                .width(64)
                TableColumn("Título", value: \.title)
                TableColumn("Artista", value: \.artist)
                TableColumn("Álbum") { c in Text(c.album ?? "—") }
                TableColumn("Ano") { c in Text(c.year ?? "") }.width(44)
                TableColumn("Faixa") { c in Text(c.trackNumber.map(String.init) ?? "") }.width(40)
                TableColumn("Duração") { c in Text(c.duration.map(LyricsBox.time) ?? "") }.width(56)
            }
            .frame(minHeight: 240)
            .overlay {
                if row?.status == .searching { ProgressView() }
                else if candidates.isEmpty { Text("Sem resultados ainda.").foregroundStyle(.secondary) }
            }
            HStack {
                Button("Buscar de novo") { model.searchCandidates(for: rowID) }
                    .disabled(model.isBusy)
                Text(model.policy == .missingOnly ? "Vai preencher só o que falta." : "Vai substituir os campos diferentes.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Usar este") {
                    if let c = candidates.first(where: { $0.id == choice }) { model.use(c, for: rowID) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(choice == nil)
            }
        }
        .padding(16)
        .frame(width: 780, height: 420)
        .onAppear {
            choice = row?.proposal?.match?.id ?? candidates.first?.id
            if candidates.isEmpty { model.searchCandidates(for: rowID) }
        }
        .onChange(of: candidates.first?.id) { _, first in if choice == nil { choice = first } }
    }
}
