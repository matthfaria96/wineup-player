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
            // Consentimento antes de qualquer consulta (inclusive a que adivinha o álbum).
            guard model.allowOnline() else { dismiss(); return }
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
        guard model.allowOnline() else { dismiss(); return }
        searching = true
        error = nil
        Task {
            do {
                results = try await model.musicBrainz.searchReleases(artist: artist, album: album)
                choice = results.first?.id
                if results.isEmpty { error = String(localized: "Nenhum álbum encontrado.") }
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
    /// Posição i = arquivo que recebe a faixa i (nil = faixa sem arquivo). Depois das faixas,
    /// os arquivos que ficam sem par. Arrastar uma linha reordena só os arquivos (como no Mp3tag).
    @State private var slots: [MetadataRow.ID?] = []
    @State private var cover: CoverImage?
    /// A capa reduzida para a caixa de 200 pt e o tamanho original, decodificados fora da thread principal.
    @State private var decoded: DecodedCover?
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
            HStack {
                Text("Faixas do álbum × seus arquivos — arraste um arquivo para cima ou para baixo para mudar o par")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu("Organizar arquivos") {
                    Button("Parear automático (título, duração, nº)") { autoPair() }
                    Button("Pela ordem do nome do arquivo") { arrange { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending } }
                    Button("Pelo nº da faixa atual") {
                        arrange { (Int($0.value("trackNumber")) ?? 999) < (Int($1.value("trackNumber")) ?? 999) }
                    }
                }
                .fixedSize()
                .controlSize(.small)
            }
            pairList
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
        .onAppear { autoPair() }
        .task {
            cover = try? await model.coverArt.frontCover(releaseID: release.id, releaseGroupID: release.releaseGroupID)
            loadingCover = false
        }
        .task(id: cover) {
            decoded = nil
            guard let data = cover?.data else { return }
            let result = await CoverDecode.decode(data, maxPixels: 400)
            guard !Task.isCancelled else { return }
            decoded = result
        }
    }

    private func sample(_ field: String) -> String {
        if let v = release.albumFields[field] { return v }
        guard let first = release.tracks.first else { return "" }
        let v = ReleaseDetail.trackFields(first)[field] ?? ""
        return String(localized: "\(v) … (por faixa)")
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
                if let image = decoded?.image {
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
                    let size = decoded?.sizeText.map { "\($0), " } ?? ""
                    return "\(size)\(c.data.count / 1024) KB, \(c.mimeType)"
                } ?? String(localized: "Capa")).font(.caption)
            }
            .disabled(cover == nil)
        }
    }

    private var pairs: [MetadataRow.ID: Int] {
        var out: [MetadataRow.ID: Int] = [:]
        for (i, id) in slots.enumerated() where i < release.tracks.count { if let id { out[id] = i } }
        return out
    }

    private func autoPair() {
        let matched = TrackMatcher.match(files: rows.map(\.file), release: release)
        var s = [MetadataRow.ID?](repeating: nil, count: release.tracks.count)
        for (id, i) in matched { s[i] = id }
        slots = s + rows.map(\.id).filter { matched[$0] == nil }.map { Optional($0) }
    }

    /// Arquivos em sequência a partir da faixa 1, na ordem pedida.
    private func arrange(_ by: (MetadataRow, MetadataRow) -> Bool) {
        let ordered = rows.sorted(by: by).map { Optional($0.id) }
        let padding = max(0, release.tracks.count - ordered.count)
        slots = ordered + [MetadataRow.ID?](repeating: nil, count: padding)
    }

    private var pairList: some View {
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        return List {
            ForEach(Array(slots.enumerated()), id: \.offset) { i, id in
                pairRow(index: i, row: id.flatMap { byID[$0] })
            }
            .onMove { from, to in slots.move(fromOffsets: from, toOffset: to) }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
    }

    private func pairRow(index i: Int, row: MetadataRow?) -> some View {
        let track = i < release.tracks.count ? release.tracks[i] : nil
        let score = track.flatMap { t in row.map { TrackMatcher.score($0.file, t, discCount: release.discCount) } }
        return HStack(spacing: 10) {
            Group {
                if let track {
                    Text(release.discCount > 1 ? "\(track.disc)-\(track.number)" : "\(track.number)")
                        .monospacedDigit().frame(width: 34, alignment: .trailing).foregroundStyle(.secondary)
                    Text(track.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(track.duration.map(LyricsBox.time) ?? "").monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text("sem faixa — não será preenchido").foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: 330)
            Group {
                if let score {
                    Image(systemName: score >= 0.7 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(score >= 0.7 ? .green : .orange)
                        .help(score >= 0.7 ? "Título/duração conferem" : "Confira: título ou duração diferentes")
                } else {
                    Image(systemName: "arrow.left.and.right").foregroundStyle(.quaternary)
                }
            }
            .frame(width: 20)
            if let row {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                Text(row.fileName).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text(row.file.duration.map(LyricsBox.time) ?? "").monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text("— nenhum arquivo —").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 12))
        .contextMenu {
            if row != nil, track != nil {
                Button("Não preencher este arquivo") {
                    let id = slots[i]
                    slots[i] = nil
                    slots.append(id)
                }
            }
        }
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
