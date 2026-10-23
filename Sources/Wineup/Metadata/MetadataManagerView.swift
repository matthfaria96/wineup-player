import SwiftUI
import WineupLibrary

/// Janela "Metadados": lista de arquivos à direita, editor da seleção à esquerda.
struct MetadataManagerView: View {
    @ObservedObject var state: PlayerState
    @StateObject private var model: MetadataManagerModel
    @State private var pickerRow: MetadataRow.ID?
    @State private var showSettings = false
    @State private var showAlbumSearch = false
    @State private var showCoverSearch = false

    init(state: PlayerState) {
        self.state = state
        _model = StateObject(wrappedValue: MetadataManagerModel(database: state.library.database))
    }

    var body: some View {
        HSplitView {
            MetadataSidebar(model: model, onPickMatch: { pickerRow = $0 })
                .frame(minWidth: 290, idealWidth: 320, maxWidth: 380)
            VStack(spacing: 0) {
                MetadataTable(model: model, onPickMatch: { pickerRow = $0 })
                Divider()
                statusBar
            }
            .frame(minWidth: 560)
        }
        .toolbar { toolbar }
        .navigationTitle(model.folder?.lastPathComponent ?? "Metadados")
        .navigationSubtitle(model.folder.map { NavPlaces.displayPath($0) } ?? "")
        .sheet(isPresented: $showAlbumSearch) { AlbumSearchView(model: model) }
        .sheet(isPresented: $showCoverSearch) { CoverSearchView(model: model) }
        .sheet(item: Binding(get: { pickerRow.map(PickerID.init) }, set: { pickerRow = $0?.id })) { item in
            MatchPicker(model: model, rowID: item.id)
        }
        .onAppear {
            model.pauseMainPlayback = { [weak state] in if state?.isPlaying == true { state?.pause() } }
            model.openIfNeeded(state.browser.folder)
        }
        .frame(minWidth: 900, minHeight: 520)
    }

    private struct PickerID: Identifiable { let id: MetadataRow.ID }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.chooseFolder() } label: { Label("Pasta", systemImage: "folder").labelStyle(.titleAndIcon) }
                .help("Escolher outra pasta")
            Button { model.reload() } label: { Label("Analisar", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon) }
                .help("Ler de novo e analisar a pasta")
                .disabled(model.folder == nil || model.isLoading)
        }
        ToolbarItemGroup {
            Button { model.autoFix(onlySelection: false) } label: {
                Label("Corrigir tudo", systemImage: "wand.and.stars").labelStyle(.titleAndIcon)
            }
            .help("Buscar metadados, capas e letras para todas as músicas com problemas")
            .disabled(model.rows.isEmpty || model.isBusy)
            Button { showAlbumSearch = true } label: {
                Label("Buscar álbum", systemImage: "square.stack").labelStyle(.titleAndIcon)
            }
            .help("Escolher o álbum no MusicBrainz e preencher todas as faixas de uma vez (seleção ou lista)")
            .disabled(model.rows.isEmpty || model.isBusy)
            Menu {
                Button("Buscar dados de cada música selecionada") { model.autoFix(onlySelection: true) }
                    .disabled(model.selection.isEmpty)
                Button("Procurar capas…") { showCoverSearch = true }
                Divider()
                Button("Buscar letras das selecionadas") { model.fetchLyrics(onlySelection: true) }
                    .disabled(model.selection.isEmpty)
                Button("Buscar letras de todas sem letra sincronizada") { model.fetchLyrics(onlySelection: false) }
            } label: {
                Label("Buscar", systemImage: "magnifyingglass").labelStyle(.titleAndIcon)
            }
            .disabled(model.rows.isEmpty || model.isBusy)
            Button { model.save(onlySelection: false) } label: {
                Label("Salvar tudo", systemImage: "square.and.arrow.down").labelStyle(.titleAndIcon)
            }
            .help("Gravar todas as alterações pendentes (com backup)")
            .disabled(model.dirtyCount == 0 || model.isBusy)
            Button { showSettings.toggle() } label: { Label("Opções", systemImage: "gearshape") }
                .popover(isPresented: $showSettings) { MetadataSettings(model: model) }
        }
        ToolbarItem {
            Menu {
                Picker("Mostrar", selection: $model.filter) {
                    ForEach(MetadataFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(model.filter.title, systemImage: "line.3.horizontal.decrease.circle")
                    .labelStyle(.titleAndIcon)
            }
            .fixedSize()
            .help("Mostrar todas, só as com problemas, as alteradas ou as duplicadas")
        }
        ToolbarItem {
            TextField("Filtrar", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let p = model.progress {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                    .frame(width: 140)
                Text("\(p.done) de \(p.total)").monospacedDigit()
                Button("Parar") { model.cancelWork() }.controlSize(.small)
            } else if model.isLoading {
                ProgressView().controlSize(.small)
                Text("Analisando a pasta…")
            } else if let m = model.message {
                Text(m)
            }
            Spacer()
            Text(model.footer)
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
    }
}

/// Política de preenchimento e identificação por áudio.
struct MetadataSettings: View {
    @ObservedObject var model: MetadataManagerModel

    var body: some View {
        Form {
            Picker("Ao usar um resultado", selection: $model.policy) {
                Text("Preencher só o que falta").tag(FillPolicy.missingOnly)
                Text("Substituir também o que já existe").tag(FillPolicy.overwrite)
            }
            .pickerStyle(.radioGroup)
            Section("Reconhecer pelo som (AcoustID)") {
                TextField("Chave de aplicativo", text: $model.acoustIDKey)
                Text(model.fpcalcFound
                     ? "fpcalc encontrado. Com a chave, músicas sem tags são reconhecidas pelo áudio."
                     : "Instale o Chromaprint (brew install chromaprint) e informe uma chave grátis de acoustid.org para reconhecer músicas pelo áudio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Só consulta a internet quando você pede (Corrigir tudo, Buscar, Ver resultados). Envia título, artista, álbum e duração para MusicBrainz, Cover Art Archive, LRCLIB e a busca do iTunes (só para descobrir o álbum); com AcoustID, também a impressão digital do áudio. Antes de gravar, o Wineup guarda um backup de cada arquivo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 400)
    }


}
