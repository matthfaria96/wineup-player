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
    @State private var showHistory = false
    @State private var confirmUndo = false
    @State private var showDuplicates = false

    init(state: PlayerState) {
        self.state = state
        _model = StateObject(wrappedValue: MetadataManagerModel(database: state.library.database))
    }

    var body: some View {
        HSplitView {
            MetadataSidebar(model: model, onPickMatch: { pickerRow = $0 })
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 360)
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
        .sheet(isPresented: $showHistory) { HistoryView(model: model) }
        .sheet(isPresented: $showDuplicates) { DuplicatesView(model: model) }
        .confirmationDialog("Desfazer a última gravação?", isPresented: $confirmUndo) {
            Button("Desfazer") { if let last = model.lastUndoable { model.undo(last) } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(model.lastUndoable?.items.count ?? 0) música(s) voltam às tags, capas e letras de antes.")
        }
        .sheet(item: Binding(get: { pickerRow.map(PickerID.init) }, set: { pickerRow = $0?.id })) { item in
            MatchPicker(model: model, rowID: item.id)
        }
        .onAppear {
            model.pauseMainPlayback = { [weak state] in if state?.isPlaying == true { state?.pause() } }
            model.openIfNeeded(state.browser.folder)
            model.refreshHistory()
        }
        .frame(minWidth: 900, minHeight: 520)
    }

    private struct PickerID: Identifiable { let id: MetadataRow.ID }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.chooseFolder() } label: { Label("Pasta", systemImage: "folder") }
                .help("Escolher outra pasta")
            Button { model.reload() } label: { Label("Analisar", systemImage: "arrow.clockwise") }
                .help("Ler de novo e analisar a pasta")
                .disabled(model.folder == nil || model.isLoading)
        }
        ToolbarItemGroup {
            Button { model.autoFix(onlySelection: false) } label: {
                Label("Corrigir tudo", systemImage: "wand.and.stars")
            }
            .help("Buscar metadados, capas e letras para todas as músicas com problemas")
            .disabled(model.rows.isEmpty || model.isBusy)
            Button { showAlbumSearch = true } label: {
                Label("Buscar álbum", systemImage: "square.stack")
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
                Label("Buscar", systemImage: "magnifyingglass")
            }
            .disabled(model.rows.isEmpty || model.isBusy)
            Button { model.save(onlySelection: false) } label: {
                Label("Salvar tudo", systemImage: "square.and.arrow.down")
            }
            .help("Gravar todas as alterações pendentes (com backup)")
            .disabled(model.dirtyCount == 0 || model.isBusy)
            Button { confirmUndo = model.lastUndoable != nil } label: {
                Label("Desfazer última gravação", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .help("Desfazer a última gravação (⌘Z): tags, capas e letras voltam ao que eram")
            .disabled(model.lastUndoable == nil || model.isBusy)
            Button { showDuplicates = true } label: { Label("Duplicadas", systemImage: "square.on.square") }
                .help("Comparar duplicadas e mandar as cópias piores para a Lixeira")
                .disabled(!model.rows.contains { $0.file.duplicateGroup != nil })
            Button { showHistory = true } label: { Label("Histórico", systemImage: "clock.arrow.circlepath") }
                .help("Histórico de gravações, com desfazer por lote")
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
            Text(model.footer)
                .monospacedDigit()
                .help("Seleção e total: quantidade (duração | tamanho)")
            Spacer()
            if let p = model.progress {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                    .frame(width: 140)
                Text("\(p.done) de \(p.total)").monospacedDigit()
                Button("Parar") { model.cancelWork() }.controlSize(.small)
            } else if model.isLoading {
                ProgressView().controlSize(.small)
                Text("Analisando a pasta…")
            } else if let m = model.message {
                Text(m).lineLimit(1)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
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
            Picker("Capa ao salvar", selection: $model.coverSaveMode) {
                ForEach(MetadataManagerModel.CoverSaveMode.allCases) { Text($0.title).tag($0) }
            }
            Section("Consultas online") {
                Toggle("Permitir buscar dados, capas e letras na internet", isOn: Binding(
                    get: { OnlineConsent.isGranted },
                    set: { OnlineConsent.answer = $0 ? .granted : .denied }))
                ForEach(OnlineServices.Service.allCases, id: \.self) { service in
                    Toggle(service.title, isOn: Binding(get: { OnlineServices.isOn(service) },
                                                        set: { OnlineServices.set(service, $0); model.objectWillChange.send() }))
                        .padding(.leading, 16)
                        .disabled(!OnlineConsent.isGranted)
                }
                Text(OnlineConsent.whatIsSent)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Letras: conta Musixmatch (opcional)") {
                SecureField("Token da sua conta", text: $model.musixmatchToken)
                Text("Usado só quando o catálogo principal não tem a letra. O Musixmatch bloqueia o acesso sem conta.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Reconhecer pelo som (AcoustID)") {
                TextField("Chave de aplicativo", text: $model.acoustIDKey)
                Text(model.fpcalcFound
                     ? "fpcalc encontrado. Com a chave, músicas sem tags são reconhecidas pelo áudio."
                     : "Instale o Chromaprint (brew install chromaprint) e informe uma chave grátis de acoustid.org para reconhecer músicas pelo áudio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Só consulta a internet quando você pede (Corrigir tudo, Buscar, Ver resultados). Envia título, artista, álbum e duração aos serviços de metadados, capas e letras; com AcoustID, também a impressão digital do áudio. Antes de gravar, o Wineup guarda um backup de cada arquivo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 400)
    }


}
