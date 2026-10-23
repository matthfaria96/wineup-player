import SwiftUI
import WineupLibrary

/// Histórico de gravações do gerenciador, com desfazer por lote.
struct HistoryView: View {
    @ObservedObject var model: MetadataManagerModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirm: SaveBatch?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Histórico de gravações").font(.headline)
            Text("Cada vez que você salva vira um lote. Desfazer devolve as tags, a capa e a letra de todas as músicas do lote ao que eram antes.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(model.batches) { batch in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: batch.undone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                        .foregroundStyle(batch.undone ? Color.secondary : .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(batch.items.count) música\(batch.items.count == 1 ? "" : "s") · \(batch.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 12, weight: .medium))
                        Text(names(batch)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        Text(NavPlaces.displayPath(URL(fileURLWithPath: batch.folder)))
                            .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer()
                    if batch.undone {
                        Text("Desfeito").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Button("Desfazer…") { confirm = batch }.controlSize(.small)
                    }
                }
                .padding(.vertical, 3)
            }
            .overlay { if model.batches.isEmpty { Text("Nenhuma gravação ainda.").foregroundStyle(.secondary) } }
            HStack {
                Spacer()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 460)
        .onAppear { model.refreshHistory() }
        .confirmationDialog("Desfazer esta gravação?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { batch in
            Button("Desfazer \(batch.items.count) música\(batch.items.count == 1 ? "" : "s")") { model.undo(batch) }
            Button("Cancelar", role: .cancel) {}
        } message: { batch in
            Text("As tags, capas e letras de \(names(batch)) voltam ao que eram antes desta gravação.")
        }
    }

    private func names(_ batch: SaveBatch) -> String {
        let all = batch.items.map { URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent }
        return all.prefix(3).joined(separator: ", ") + (all.count > 3 ? " e mais \(all.count - 3)" : "")
    }
}
