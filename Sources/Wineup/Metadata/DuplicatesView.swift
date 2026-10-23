import SwiftUI
import WineupLibrary

/// Duplicadas lado a lado: a cópia recomendada fica; as outras podem ir para a Lixeira (com confirmação).
struct DuplicatesView: View {
    @ObservedObject var model: MetadataManagerModel
    @Environment(\.dismiss) private var dismiss
    @State private var marked: Set<String> = []
    @State private var confirm = false

    private var groups: [(group: Int, files: [FixerFile])] { DuplicateRanking.groups(model.rows.map(\.file)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Duplicadas").font(.headline)
            Text("Mesma música (artista e título) com duração parecida. A primeira de cada grupo é a recomendada para manter. Marque o que deve ir para a Lixeira; nada é apagado sem confirmar, e dá para recuperar pela Lixeira.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(groups, id: \.group) { group in
                    Section(group.files.first.map { "\($0.value("artist")) — \($0.value("title").isEmpty ? $0.url.deletingPathExtension().lastPathComponent : $0.value("title"))" } ?? "") {
                        ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                            row(file, best: index == 0 ? nil : group.files[0], isBest: index == 0)
                        }
                    }
                }
            }
            .overlay { if groups.isEmpty { Text("Nenhuma duplicada nesta pasta.").foregroundStyle(.secondary) } }
            HStack {
                Text("\(marked.count) marcada(s)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Mover para a Lixeira…") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(marked.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 860, height: 560)
        .onAppear { marked = Set(groups.flatMap { $0.files.dropFirst().map(\.url.path) }) }
        .confirmationDialog("Mover \(marked.count) arquivo(s) para a Lixeira?", isPresented: $confirm) {
            Button("Mover para a Lixeira", role: .destructive) {
                model.trash(paths: marked)
                marked = []
                if groups.isEmpty { dismiss() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("A letra (.lrc) ao lado de cada um vai junto. Você pode recuperar pela Lixeira do Finder.")
        }
    }

    private func row(_ file: FixerFile, best: FixerFile?, isBest: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { marked.contains(file.url.path) },
                                     set: { if $0 { marked.insert(file.url.path) } else { marked.remove(file.url.path) } }))
                .labelsHidden()
                .help("Mover este arquivo para a Lixeira")
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent).font(.system(size: 12, weight: isBest ? .semibold : .regular)).lineLimit(1)
                Text(NavPlaces.displayPath(file.url.deletingLastPathComponent()))
                    .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Group {
                Text(file.url.pathExtension.uppercased()).frame(width: 44)
                Text(file.tech.bitrateText).frame(width: 74, alignment: .trailing)
                Text(file.duration.map(LyricsBox.time) ?? "").frame(width: 40, alignment: .trailing)
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).frame(width: 64, alignment: .trailing)
                Image(systemName: "photo").foregroundStyle(file.hasCover ? Color.secondary : Color.secondary.opacity(0.25))
                    .help(file.hasCover ? "Tem capa" : "Sem capa")
                Image(systemName: "text.quote").foregroundStyle(file.hasLyrics ? Color.secondary : Color.secondary.opacity(0.25))
                    .help(file.hasLyrics ? "Tem letra" : "Sem letra")
            }
            .font(.system(size: 11)).monospacedDigit()
            Text(isBest ? "Manter" : best.map { "melhor: a 1ª (\(DuplicateRanking.reason(best: $0, other: file)))" } ?? "")
                .font(.system(size: 10, weight: isBest ? .semibold : .regular))
                .foregroundStyle(isBest ? Color.green : .secondary)
                .frame(width: 190, alignment: .leading)
                .lineLimit(1)
        }
    }
}
