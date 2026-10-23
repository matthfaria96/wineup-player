import SwiftUI
import WineupLibrary

/// Busca por álbum em duas etapas, como a Fonte de Etiquetas do Mp3tag:
/// 1) artista + álbum → lista de lançamentos; 2) campos marcáveis, capa e faixas × arquivos.
struct AlbumSearchView: View {
    @ObservedObject var model: MetadataManagerModel
    @Environment(\.dismiss) private var dismiss

    @State private var artist = ""
    @State private var album = ""
    @State private var results: [ReleaseSummary] = []
    @State private var choice: ReleaseSummary.ID?
    @State private var searching = false
    @State private var error: String?
    @State private var release: ReleaseDetail?
    @State private var loadingRelease = false

    var body: some View {
        VStack(spacing: 0) {
            if let release {
                AlbumApplyView(model: model, release: release, onBack: { self.release = nil }, onDone: { dismiss() })
            } else {
                searchStep
            }
        }
        .frame(width: 960, height: 640)
        .onAppear {
            let q = model.albumQuery
            artist = q.artist
            album = q.album
            Task {
                if album.isEmpty, let hint = await model.suggestAlbum() { album = hint }
                if !artist.isEmpty || !album.isEmpty { search() }
            }
        }
    }

    private var searchStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Artista:").gridColumnAlignment(.trailing)
                    TextField("", text: $artist).textFieldStyle(.roundedBorder).onSubmit(search)
                    Button("Buscar", action: search).keyboardShortcut(.defaultAction).disabled(searching)
                }
                GridRow {
                    Text("Álbum:")
                    TextField("", text: $album).textFieldStyle(.roundedBorder).onSubmit(search)
                    Text("\(model.albumTargets.count) músicas").font(.caption).foregroundStyle(.secondary)
                }
            }
            Table(results, selection: $choice) {
                TableColumn("") { r in CoverThumb(releaseID: r.id, size: 28) }.width(32)
                TableColumn("Pontuação") { r in Text("\(r.score)").monospacedDigit() }.width(64)
                TableColumn("Tipo", value: \.type).width(min: 50, ideal: 80)
                TableColumn("Artista", value: \.artist).width(min: 80, ideal: 120)
                TableColumn("Álbum", value: \.title).width(min: 120, ideal: 200)
                TableColumn("Faixas") { r in Text("\(r.trackCount)").monospacedDigit() }.width(44)
                TableColumn("Ano") { r in Text(r.year ?? "") }.width(40)
                TableColumn("País") { r in Text(r.country ?? "") }.width(36)
                TableColumn("Formato") { r in Text(r.format ?? "") }.width(min: 50, ideal: 80)
                TableColumn("Gravadora · Catálogo") { r in
                    Text([r.label, r.catalogNumber].compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
                }
                .width(min: 80, ideal: 170)
            }
            .contextMenu(forSelectionType: ReleaseSummary.ID.self) { _ in } primaryAction: { _ in next() }
            .overlay {
                if searching { ProgressView() }
                else if let error { Text(error).foregroundStyle(.secondary) }
                else if results.isEmpty { Text("Digite artista e álbum e clique em Buscar.").foregroundStyle(.secondary) }
            }
            HStack {
                if let id = choice {
                    Link("Ver no MusicBrainz", destination: URL(string: "https://musicbrainz.org/release/\(id)")!)
                        .font(.caption)
                }
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(loadingRelease ? "Carregando…" : "Próximo", action: next)
                    .buttonStyle(.borderedProminent)
                    .disabled(choice == nil || loadingRelease)
            }
        }
        .padding(16)
    }

    private func search() {
        searching = true
        error = nil
        Task {
            do {
                results = try await model.musicBrainz.searchReleases(artist: artist, album: album)
                choice = results.first?.id
                if results.isEmpty { error = "Nenhum álbum encontrado." }
            } catch {
                self.error = MetadataManagerModel.describe(error)
            }
            searching = false
        }
    }

    private func next() {
        guard let id = choice else { return }
        loadingRelease = true
        Task {
            do { release = try await model.musicBrainz.release(id: id) } catch {
                self.error = MetadataManagerModel.describe(error)
            }
            loadingRelease = false
        }
    }
}

/// Etapa 2: o que gravar (campos marcáveis), a capa, e cada arquivo com a sua faixa.
struct AlbumApplyView: View {
    @ObservedObject var model: MetadataManagerModel
    let release: ReleaseDetail
    let onBack: () -> Void
    let onDone: () -> Void

    @State private var fields: Set<String> = ["album", "albumArtist", "year", "genre", "title", "artist", "trackNumber", "discNumber"]
    @State private var pairs: [MetadataRow.ID: Int] = [:]
    @State private var cover: CoverImage?
    @State private var useCover = true
    @State private var loadingCover = true

    private var rows: [MetadataRow] { model.albumTargets }
    private static let order = ["album", "albumArtist", "year", "genre", "title", "artist", "trackNumber", "discNumber"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                fieldList
                coverBox
            }
            .frame(height: 230)
            Text("Faixas do álbum × seus arquivos — troque o par pelo menu de cada arquivo")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            pairTable
            HStack {
                Button("Voltar", action: onBack)
                Text("\(pairs.count) de \(rows.count) arquivos com faixa").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar", action: onDone).keyboardShortcut(.cancelAction)
                Button("Aplicar") {
                    model.applyRelease(release, pairs: pairs, fields: fields, cover: useCover ? cover : nil)
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(pairs.isEmpty || fields.isEmpty && !useCover)
                .help("Preenche as músicas como alteração pendente; nada é gravado até Salvar")
            }
        }
        .padding(16)
        .onAppear {
            pairs = TrackMatcher.match(files: rows.map(\.file), release: release)
        }
        .task {
            cover = try? await model.coverArt.frontCover(releaseID: release.id, releaseGroupID: release.releaseGroupID)
            loadingCover = false
        }
    }

    private func sample(_ field: String) -> String {
        if let v = release.albumFields[field] { return v }
        guard let first = release.tracks.first else { return "" }
        let v = ReleaseDetail.trackFields(first)[field] ?? ""
        return "\(v) … (por faixa)"
    }

    private var fieldList: some View {
        List {
            ForEach(Self.order, id: \.self) { field in
                Toggle(isOn: Binding(get: { fields.contains(field) },
                                     set: { on in if on { fields.insert(field) } else { fields.remove(field) } })) {
                    HStack {
                        Text(MetadataFieldName.label(field)).frame(width: 120, alignment: .leading)
                        Text(sample(field)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
    }

    private var coverBox: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3))
                if let image = cover.flatMap({ NSImage(data: $0.data) }) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else if loadingCover {
                    ProgressView()
                } else {
                    Text("Sem capa no Cover Art Archive").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)
            Toggle(isOn: $useCover) {
                Text(cover.map { c in
                    let size = NSImage(data: c.data).map { "\(Int($0.size.width))×\(Int($0.size.height)), " } ?? ""
                    return "\(size)\(c.data.count / 1024) KB, \(c.mimeType)"
                } ?? "Capa").font(.caption)
            }
            .disabled(cover == nil)
        }
    }

    private var pairTable: some View {
        Table(rows) {
            TableColumn("Arquivo") { row in Text(row.fileName).lineLimit(1) }.width(min: 160, ideal: 260)
            TableColumn("Duração") { row in Text(row.file.duration.map(LyricsBox.time) ?? "").monospacedDigit() }.width(56)
            TableColumn("Faixa do álbum") { row in trackPicker(row) }.width(min: 200, ideal: 340)
            TableColumn("Duração") { row in
                Text(pairs[row.id].flatMap { release.tracks[$0].duration }.map(LyricsBox.time) ?? "").monospacedDigit()
            }
            .width(56)
            TableColumn("Confere") { row in
                if let i = pairs[row.id] {
                    let s = TrackMatcher.score(row.file, release.tracks[i], discCount: release.discCount)
                    Image(systemName: s >= 0.7 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(s >= 0.7 ? .green : .orange)
                        .help(s >= 0.7 ? "Título/duração conferem" : "Confira: título ou duração diferentes")
                }
            }
            .width(56)
        }
    }

    private func trackPicker(_ row: MetadataRow) -> some View {
        Picker("", selection: Binding(
            get: { pairs[row.id] ?? -1 },
            set: { new in
                if new >= 0, let other = pairs.first(where: { $0.value == new && $0.key != row.id })?.key {
                    pairs[other] = pairs[row.id]   // troca: a outra fica com a faixa antiga desta
                }
                pairs[row.id] = new >= 0 ? new : nil
            })) {
            Text("— não preencher —").tag(-1)
            ForEach(Array(release.tracks.enumerated()), id: \.offset) { i, t in
                Text(release.discCount > 1 ? "\(t.disc)-\(t.number). \(t.title)" : "\(t.number). \(t.title)").tag(i)
            }
        }
        .labelsHidden()
    }
}

/// Miniatura da capa de um lançamento (Cover Art Archive, 250 px), carregada sob demanda.
struct CoverThumb: View {
    let releaseID: String
    var size: CGFloat = 28

    var body: some View {
        AsyncImage(url: URL(string: "https://coverartarchive.org/release/\(releaseID)/front-250")) { phase in
            if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
