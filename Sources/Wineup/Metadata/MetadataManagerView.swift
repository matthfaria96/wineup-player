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
    @State private var showQueue = false

    init(state: PlayerState) {
        self.state = state
        _model = StateObject(wrappedValue: MetadataManagerModel(database: state.library.database))
    }

    var body: some View {
        HSplitView {
            MetadataSidebar(model: model)
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 360)
            VStack(spacing: 0) {
                if SaveBanner.isShown(model) {
                    SaveBanner(model: model).transition(.move(edge: .top).combined(with: .opacity))
                }
                MetadataTable(model: model, onPickMatch: { pickerRow = $0 })
                if showQueue && !model.workIDs.isEmpty {
                    WorkQueuePanel(model: model, onHide: { showQueue = false })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Divider()
                statusBar
            }
            .themedSurface(list: true)
            .animation(.snappy, value: SaveBanner.isShown(model))
            .animation(.snappy, value: showQueue)
            .frame(minWidth: 560)
        }
        .toolbar { toolbar }
        .navigationTitle(model.folder?.lastPathComponent ?? String(localized: "Metadados"))
        .navigationSubtitle(model.folder.map { NavPlaces.displayPath($0) } ?? "")
        .sheet(isPresented: $showAlbumSearch) { AlbumSearchView(model: model).themedWindow() }
        .sheet(isPresented: $showCoverSearch) { CoverSearchView(model: model).themedWindow() }
        .sheet(isPresented: $showHistory) { HistoryView(model: model).themedWindow() }
        .sheet(isPresented: $showDuplicates) { DuplicatesView(model: model).themedWindow() }
        .sheet(item: $model.report) { SearchReportView(report: $0, model: model).themedWindow() }
        // A busca começa: o painel de cards sobe sozinho; ao terminar, fica até o usuário fechar.
        .onChange(of: model.searchRuns) { showQueue = true }
        .onChange(of: model.pickRequest) { _, id in
            guard let id else { return }
            pickerRow = id
            model.pickRequest = nil
        }
        .confirmationDialog("Desfazer a última gravação?", isPresented: $confirmUndo) {
            Button("Desfazer") { if let last = model.lastUndoable { model.undo(last) } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(model.lastUndoable?.items.count ?? 0) música(s) voltam às tags, capas e letras de antes.")
        }
        .sheet(item: Binding(get: { pickerRow.map(PickerID.init) }, set: { pickerRow = $0?.id })) { item in
            MatchPicker(model: model, rowID: item.id).themedWindow()
        }
        .onAppear {
            model.pauseMainPlayback = { [weak state] in if state?.isPlaying == true { state?.pause() } }
            model.openIfNeeded(state.browser.folder)
            if Measure.stress { StressRun.metadata = model }
            model.refreshHistory()
            applyTestHooks()
        }
        // Janela fechada: a busca para (o resultado não teria onde aparecer); uma gravação termina o bloco.
        .onDisappear { model.windowClosed() }
        .frame(minWidth: 900, minHeight: 520)
    }

    private struct PickerID: Identifiable { let id: MetadataRow.ID }

    /// Testes e capturas: abre uma subtela ou seleciona uma música ao abrir (sem cliques).
    private func applyTestHooks() {
        // Testes: WINEUP_METADATA_SHEET=album|cover|history|duplicates abre essa tela (capturas sem clicar).
        switch ProcessInfo.processInfo.environment["WINEUP_METADATA_SHEET"] {
        case "album": showAlbumSearch = true
        case "cover": showCoverSearch = true
        case "history": showHistory = true
        case "duplicates": showDuplicates = true
        default: break
        }
        // Testes: WINEUP_METADATA_SELECT=<parte do nome do arquivo> seleciona essa música (mostra o editor ao lado).
        if let want = ProcessInfo.processInfo.environment["WINEUP_METADATA_SELECT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if let row = model.visibleRows.first(where: { $0.fileName.localizedCaseInsensitiveContains(want) }) {
                    model.selection = [row.id]
                }
            }
        }
    }

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
            // A ação principal, com nome: busca tudo o que falta nas músicas com problemas.
            Button { model.autoFix(onlySelection: false) } label: {
                Label("Corrigir tudo", systemImage: "wand.and.stars")
            }
            .labelStyle(.titleAndIcon)
            .help("Buscar metadados, capas e letras para todas as músicas com problemas")
            .disabled(model.rows.isEmpty || model.isBusy)
            Menu {
                Button("Buscar dados das selecionadas") { model.autoFix(onlySelection: true) }
                    .disabled(model.selection.isEmpty)
                Button("Buscar o álbum no MusicBrainz…") { showAlbumSearch = true }
                Button("Procurar capas…") { showCoverSearch = true }
                Divider()
                Button("Buscar letras das selecionadas") { model.fetchLyrics(onlySelection: true) }
                    .disabled(model.selection.isEmpty)
                Button("Buscar letras de todas sem letra sincronizada") { model.fetchLyrics(onlySelection: false) }
            } label: {
                Label("Buscar", systemImage: "magnifyingglass")
            }
            .help("Buscar só as selecionadas, um álbum inteiro, capas ou letras")
            .disabled(model.rows.isEmpty || model.isBusy)
            // Desfazer e o histórico juntos: o desfazer é só o atalho para o último lote do histórico.
            Menu {
                Button("Desfazer a última gravação") { confirmUndo = model.lastUndoable != nil }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.lastUndoable == nil || model.isBusy)
                Button("Ver histórico de gravações…") { showHistory = true }
            } label: {
                Label("Histórico", systemImage: "clock.arrow.circlepath")
            }
            .help("Desfazer a última gravação (⌘Z) ou qualquer lote anterior")
            Button { showSettings.toggle() } label: { Label("Opções", systemImage: "gearshape") }
                .help("Como aplicar os resultados e quais serviços online usar")
                .popover(isPresented: $showSettings) { MetadataSettings(model: model) }
        }
        ToolbarItem {
            Menu {
                Picker("Mostrar", selection: $model.filter) {
                    ForEach(MetadataFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Comparar duplicadas…") { showDuplicates = true }
                    .disabled(!model.hasDuplicates)
            } label: {
                Label(model.filter.title, systemImage: "line.3.horizontal.decrease.circle")
                    
            }
            .fixedSize()
            .help("Mostrar todas, só as com problemas, para revisar, alteradas ou duplicadas")
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
            if !model.workIDs.isEmpty {
                Button { showQueue.toggle() } label: {
                    HStack(spacing: 6) {
                        if let p = model.progress {
                            ProgressView(value: Double(p.done), total: Double(max(p.total, 1))).frame(width: 140)
                            Text("\(p.done) de \(p.total)").monospacedDigit()
                        } else if let m = model.message {
                            Text(m).lineLimit(1)
                        }
                        Label(showQueue ? "Recolher" : "Ver músicas", systemImage: "chevron.up")
                            .labelStyle(.titleAndIcon)
                            .imageScale(.small)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .rotationEffect(.zero)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showQueue ? "Esconder as músicas da busca" : "Ver cada música da busca e o estado dela")
                if model.progress != nil { Button("Parar") { model.cancelWork() }.controlSize(.small) }
            } else if let p = model.progress {
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
        .themedSurface()
    }
}

/// Opções da busca de metadados: como aplicar resultados, consultas online, Musixmatch e AcoustID.
struct MetadataSettings: View {
    @ObservedObject var model: MetadataManagerModel

    var body: some View {
        Form {
            Section {
                Picker("Ao usar um resultado", selection: $model.policy) {
                    Text("Preencher só o que falta").tag(FillPolicy.missingOnly)
                    Text("Substituir o que já existe").tag(FillPolicy.overwrite)
                }
                Picker("Capa ao salvar", selection: $model.coverSaveMode) {
                    ForEach(MetadataManagerModel.CoverSaveMode.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Resultados")
            } footer: {
                Text("Nada é gravado até você salvar. Antes de gravar, o Wineup guarda um backup de cada arquivo.")
            }

            Section {
                Toggle("Buscar na internet", isOn: Binding(
                    get: { OnlineConsent.isGranted },
                    set: { OnlineConsent.answer = $0 ? .granted : .denied; model.objectWillChange.send() }))
                ForEach(OnlineServices.Service.allCases, id: \.self) { service in
                    Toggle(isOn: Binding(get: { OnlineServices.isOn(service) },
                                         set: { OnlineServices.set(service, $0); model.objectWillChange.send() })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.title(service))
                            Text(Self.detail(service)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!OnlineConsent.isGranted)
                }
            } header: {
                Text("Consultas online")
            } footer: {
                Text("Só consulta quando você pede. Envia título, artista, álbum e duração; o áudio nunca é enviado.")
            }

            Section {
                SecureField("Token", text: $model.musixmatchToken, prompt: Text("Opcional"))
            } header: {
                Text("Letras: conta Musixmatch")
            } footer: {
                Text("Usado só quando o catálogo principal não tem a letra. O Musixmatch exige uma conta.")
            }

            Section {
                TextField("Chave", text: $model.acoustIDKey, prompt: Text("Opcional"))
                LabeledContent("Chromaprint") {
                    Label(model.fpcalcFound ? "Instalado" : "Não instalado",
                          systemImage: model.fpcalcFound ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(model.fpcalcFound ? .green : .secondary)
                }
            } header: {
                Text("Reconhecer pelo som (AcoustID)")
            } footer: {
                Text(model.fpcalcFound
                     ? "Com a chave, músicas sem tags são reconhecidas pelo áudio (só a impressão digital do som é enviada)."
                     : "Instale com brew install chromaprint e crie uma chave grátis em acoustid.org.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 560)
    }

    private static func title(_ service: OnlineServices.Service) -> String {
        switch service {
        case .metadata: String(localized: "Dados e capas de álbuns")
        case .albumHint: String(localized: "Descobrir o álbum")
        case .lyrics: String(localized: "Letras")
        }
    }

    private static func detail(_ service: OnlineServices.Service) -> String {
        switch service {
        case .metadata: String(localized: "MusicBrainz e Cover Art Archive")
        case .albumHint: String(localized: "Busca do iTunes, também para capas extras")
        case .lyrics: String(localized: "Catálogos de letras sincronizadas")
        }
    }
}
