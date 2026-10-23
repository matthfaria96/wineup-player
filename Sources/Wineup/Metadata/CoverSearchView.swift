import SwiftUI
import WineupLibrary

/// "Procurar capas": lista de álbuns com miniatura, prévia grande com tamanho, escolha da fonte.
struct CoverSearchView: View {
    @ObservedObject var model: MetadataManagerModel
    @Environment(\.dismiss) private var dismiss
    @State private var artist = ""
    @State private var album = ""
    @State private var source: CoverCandidate.Source = .musicBrainz
    @State private var results: [CoverCandidate] = []
    @State private var choice: CoverCandidate.ID?
    @State private var preview: CoverImage?
    @State private var loading = false
    @State private var searching = false
    @State private var error: String?

    private let search = CoverSearch()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Artista:").gridColumnAlignment(.trailing)
                    TextField("", text: $artist).textFieldStyle(.roundedBorder).onSubmit(run)
                    Button("Buscar", action: run).keyboardShortcut(.defaultAction)
                }
                GridRow {
                    Text("Álbum:")
                    TextField("", text: $album).textFieldStyle(.roundedBorder).onSubmit(run)
                    Picker("", selection: $source) {
                        ForEach(CoverCandidate.Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            HStack(spacing: 0) {
                List(results, selection: $choice) { c in
                    HStack(spacing: 10) {
                        AsyncImage(url: c.thumbURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
                        }
                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 3))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text([c.artist, c.date].compactMap { $0 }.joined(separator: " – ")).font(.system(size: 11))
                                .foregroundStyle(.secondary).lineLimit(1)
                            if let d = c.detail, !d.isEmpty { Text(d).font(.system(size: 10)).foregroundStyle(.tertiary) }
                        }
                    }
                    .tag(c.id)
                }
                .frame(width: 300)
                VStack(spacing: 6) {
                    ZStack {
                        Color.black.opacity(0.3)
                        if let image = preview.flatMap({ NSImage(data: $0.data) }) {
                            Image(nsImage: image).resizable().scaledToFit()
                        } else if loading || searching {
                            ProgressView()
                        } else {
                            Text(error ?? (results.isEmpty ? "Busque por artista e álbum." : "Sem imagem para este álbum."))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Vai para \(model.selection.isEmpty ? "nenhuma música (selecione na lista)" : "\(model.selection.count) música(s) selecionada(s)")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Usar esta capa") {
                    model.setCover(preview)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview == nil || model.selection.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 920, height: 640)
        .onAppear {
            let q = model.albumQuery
            artist = q.artist
            album = q.album
            // Consentimento antes de qualquer consulta (inclusive a que adivinha o álbum).
            guard model.allowOnline() else { dismiss(); return }
            Task {
                if album.isEmpty, let hint = await model.suggestAlbum() { album = hint }
                if !artist.isEmpty || !album.isEmpty { run() }
            }
        }
        .onChange(of: source) { _, _ in run() }
        .onChange(of: choice) { _, id in load(id) }
    }

    private var caption: String {
        guard let p = preview, let image = NSImage(data: p.data) else { return " " }
        let px = image.representations.first.map { "\($0.pixelsWide)×\($0.pixelsHigh)" } ?? ""
        return "\(px), \(p.data.count / 1024) KB, \(p.mimeType)"
    }

    private func run() {
        guard model.allowOnline() else { dismiss(); return }
        searching = true
        error = nil
        preview = nil
        Task {
            do {
                results = try await search.search(artist: artist, album: album, source: source)
                choice = results.first?.id
                if results.isEmpty { error = "Nenhum álbum encontrado." }
            } catch {
                self.error = MetadataManagerModel.describe(error)
            }
            searching = false
        }
    }

    private func load(_ id: CoverCandidate.ID?) {
        preview = nil
        guard let c = results.first(where: { $0.id == id }) else { return }
        loading = true
        Task {
            let image = try? await search.download(c)
            if choice == c.id { preview = image; loading = false }
        }
    }
}
