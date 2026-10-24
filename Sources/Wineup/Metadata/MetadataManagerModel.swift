import AppKit
import SwiftUI
import Foundation
import WineupLibrary

/// Estado do gerenciador de metadados: pasta, análise, busca nas bases e gravação segura.
@MainActor
final class MetadataManagerModel: ObservableObject {
    static let acoustIDKeyDefaults = "metadata.acoustIDKey"
    static let policyDefaults = "metadata.fillPolicy"

    @Published private(set) var folder: URL?
    /// Só o próprio modelo troca as linhas (sempre de uma vez, numa cópia): assim os caches abaixo valem.
    @Published private(set) var rows: [MetadataRow] = [] { didSet { rowsVersion &+= 1 } }
    @Published var selection: Set<MetadataRow.ID> = [] { didSet { selectionVersion &+= 1 } }
    @Published var filter: MetadataFilter = .all { didSet { listVersion &+= 1 } }
    /// Texto do campo Filtrar; a lista usa `appliedQuery`, aplicado um instante depois da última tecla.
    @Published var query = "" { didSet { scheduleQuery() } }
    @Published private var appliedQuery = "" { didSet { listVersion &+= 1 } }
    /// Colunas visíveis/ordem/largura (clique direito no cabeçalho), lembradas entre aberturas.
    @Published var columnCustomization: TableColumnCustomization<MetadataRow> = MetadataManagerModel.loadColumns() {
        didSet { scheduleColumnsSave() }
    }
    /// v3: Nome com a capa e a confiança embutidas; Duração e Letra logo depois; depois Caminho, Título, Artista,
    /// Álbum e Ano. A ordem salva nas versões anteriores escondia isso; só o mostrar/esconder é aproveitado.
    static let columnsKey = "metadata.columns.v3"

    static func loadColumns() -> TableColumnCustomization<MetadataRow> {
        if let data = UserDefaults.standard.data(forKey: columnsKey),
           let saved = try? JSONDecoder().decode(TableColumnCustomization<MetadataRow>.self, from: data) {
            return saved
        }
        // Começa como o Mp3tag: técnicas visíveis, extras do Wineup escondidas até o usuário pedir.
        var c = TableColumnCustomization<MetadataRow>()
        for id in ["comment", "composer", "samplerate", "size"] { c[visibility: id] = .hidden }
        // Quem já tinha escolhido colunas na v1 mantém o que mostrou/escondeu (só a ordem recomeça).
        if let data = UserDefaults.standard.data(forKey: "metadata.columns.v2") ?? UserDefaults.standard.data(forKey: "metadata.columns.v1"),
           let old = try? JSONDecoder().decode(TableColumnCustomization<MetadataRow>.self, from: data) {
            for id in ["path", "tag", "title", "track", "artist", "albumArtist", "album", "disc", "year", "genre", "comment",
                       "composer", "codec", "bitrate", "samplerate", "duration", "size", "lyrics"] {
                c[visibility: id] = old[visibility: id]
            }
        }
        return c
    }

    @Published var sortOrder: [KeyPathComparator<MetadataRow>] = [KeyPathComparator(\.sortFile)] {
        didSet { listVersion &+= 1 }
    }
    @Published private(set) var isLoading = false
    /// Gravado só pelas tarefas do modelo (busca, gravação, desfazer).
    @Published var progress: (done: Int, total: Int)?
    @Published var message: String?
    /// Músicas da busca em andamento (ou da última), na ordem: o painel de cards do rodapé mostra estas.
    @Published private(set) var workIDs: [MetadataRow.ID] = []
    /// Resumo da última busca, mostrado quando ela termina.
    @Published var report: SearchReport?
    @Published var policy: FillPolicy {
        didSet { UserDefaults.standard.set(policy.rawValue, forKey: Self.policyDefaults) }
    }
    @Published var musixmatchToken = UserDefaults.standard.string(forKey: LyricsService.musixmatchTokenKey) ?? "" {
        didSet { UserDefaults.standard.set(musixmatchToken, forKey: LyricsService.musixmatchTokenKey) }
    }
    @Published var acoustIDKey: String {
        didSet { UserDefaults.standard.set(acoustIDKey, forKey: Self.acoustIDKeyDefaults) }
    }

    /// Pausa o player principal antes da prévia da letra tocar (senão saem duas músicas juntas).
    var pauseMainPlayback: (() -> Void)?
    let writer: TagWriter?
    /// Tarefa em andamento (busca, gravação ou desfazer). Trocar avisa a tela (`isBusy`).
    var work: Task<Void, Never>? { willSet { objectWillChange.send() } }
    /// Cada tarefa nova ganha um número; resultado de uma tarefa velha (cancelada) é descartado.
    private(set) var workToken = 0
    private var loadToken = 0
    private var queryTask: Task<Void, Never>?
    private var columnsSaveTask: Task<Void, Never>?
    private var coverTasks: [MetadataRow.ID: Task<Void, Never>] = [:]
    /// Última gravação da lista de ignorados (as seguintes esperam esta, para não inverter a ordem).
    var ignoreWrite: Task<Void, Never>?

    // Caches derivados das linhas, refeitos só quando a versão muda.
    private var rowsVersion = 0
    private var selectionVersion = 0
    private var listVersion = 0
    /// Muda quando as linhas mostradas (conteúdo, ordem, filtro ou texto) mudam: a tabela só recarrega aí.
    struct ListStamp: Equatable { let rows: Int; let list: Int }
    var listStamp: ListStamp { ListStamp(rows: rowsVersion, list: listVersion) }
    private var rowIndex = RowIndex<MetadataRow.ID>([])
    private var visibleCache: (rows: Int, list: Int, value: [MetadataRow])?
    private var selectedCache: (rows: Int, selection: Int, value: [MetadataRow])?
    private var dirtyCache: (rows: Int, value: Int)?
    private var reviewCache: (rows: Int, value: Int)?
    private var summaryCache: (rows: Int, value: CollectionCounts)?
    private var groupsCache: (rows: Int, value: [(group: Int, files: [FixerFile])])?
    private var totalCache: (rows: Int, value: String)?
    private var fieldCache: (rows: Int, selection: Int, values: [String: FieldState])?

    init(database: LibraryDatabase?) {
        writer = database.map { TagWriter(database: $0, backups: BackupStore()) }
        policy = FillPolicy(rawValue: UserDefaults.standard.string(forKey: Self.policyDefaults) ?? "") ?? .missingOnly
        acoustIDKey = UserDefaults.standard.string(forKey: Self.acoustIDKeyDefaults) ?? ""
    }

    var fpcalcFound: Bool { AcoustIDClient.fpcalcPath() != nil }
    var isBusy: Bool { work != nil }
    /// Pedido para abrir a escolha de resultado de uma música (a janela mostra a folha e limpa o pedido).
    @Published var pickRequest: MetadataRow.ID?
    /// Conta as buscas iniciadas: só elas abrem a fila de cards (salvar e desfazer não).
    @Published private(set) var searchRuns = 0

    private var fixer: MetadataFixer {
        let key = acoustIDKey.trimmingCharacters(in: .whitespaces)
        return MetadataFixer(acoustID: key.isEmpty ? nil : AcoustIDClient(apiKey: key))
    }

    // MARK: Lista

    /// Filtradas e ordenadas; recalculadas só quando linhas, filtro, texto ou ordem mudam.
    var visibleRows: [MetadataRow] {
        if let c = visibleCache, c.rows == rowsVersion, c.list == listVersion { return c.value }
        let value = Self.visible(rows, filter: filter, query: TextMatch.normalize(appliedQuery), sortOrder: sortOrder)
        visibleCache = (rowsVersion, listVersion, value)
        return value
    }

    /// Ordena pelas chaves já calculadas de cada linha (lidas uma vez), não com o comparador localizado
    /// da tabela a cada comparação: 5 mil linhas ordenavam em ~100 ms na thread principal.
    static func visible(_ rows: [MetadataRow], filter: MetadataFilter, query: String,
                        sortOrder: [KeyPathComparator<MetadataRow>]) -> [MetadataRow] {
        let kept = rows.filter { filter.includes($0) && ManagerSearch.matches(key: $0.keys.search, query: query) }
        guard !sortOrder.isEmpty else { return kept }
        let paths = sortOrder.map(\.keyPath)
        let keys = kept.map { row in paths.map { SortValue(any: row[keyPath: $0]) } }
        return ManagerSort.order(keys, ascending: sortOrder.map { $0.order == .forward }).map { kept[$0] }
    }

    var selectedRows: [MetadataRow] {
        if let c = selectedCache, c.rows == rowsVersion, c.selection == selectionVersion { return c.value }
        let value = positions(of: selection).map { rows[$0] }
        selectedCache = (rowsVersion, selectionVersion, value)
        return value
    }

    var dirtyCount: Int {
        if let c = dirtyCache, c.rows == rowsVersion { return c.value }
        let value = rows.reduce(0) { $0 + ($1.isDirty ? 1 : 0) }
        dirtyCache = (rowsVersion, value)
        return value
    }

    /// Encontradas com pouca confiança, à espera de o usuário escolher o resultado.
    var reviewCount: Int {
        if let c = reviewCache, c.rows == rowsVersion { return c.value }
        let value = rows.reduce(0) { $0 + ($1.needsReview ? 1 : 0) }
        reviewCache = (rowsVersion, value)
        return value
    }

    /// Contagem dos problemas abertos (resumo da pasta), numa passada só.
    var summary: CollectionCounts {
        if let c = summaryCache, c.rows == rowsVersion { return c.value }
        let open = rows.map(\.openIssues)
        let value = CollectionCounts(issues: IssueCounts.count(open), withProblems: open.filter { !$0.isEmpty }.count)
        summaryCache = (rowsVersion, value)
        return value
    }

    /// Grupos de duplicadas, cada um com a cópia recomendada primeiro.
    var duplicateGroups: [(group: Int, files: [FixerFile])] {
        if let c = groupsCache, c.rows == rowsVersion { return c.value }
        let value = DuplicateRanking.groups(rows.map(\.file))
        groupsCache = (rowsVersion, value)
        return value
    }

    var hasDuplicates: Bool { !duplicateGroups.isEmpty }

    func index(of id: MetadataRow.ID) -> Int? {
        guard let i = rowIndex[id], rows.indices.contains(i), rows[i].id == id else { return nil }
        return i
    }

    func row(_ id: MetadataRow.ID) -> MetadataRow? { index(of: id).map { rows[$0] } }

    /// Posições (em ordem) das linhas pedidas que existem.
    func positions<S: Sequence>(of ids: S) -> [Int] where S.Element == MetadataRow.ID {
        rowIndex.positions(of: ids).filter { rows.indices.contains($0) }
    }

    /// Troca a lista inteira (outra pasta, linhas removidas) e refaz o índice.
    func replaceRows(_ new: [MetadataRow]) {
        rowIndex = RowIndex(new.map(\.id))
        rows = new
    }

    /// Muda as linhas pedidas numa cópia e publica uma vez só (nada muda se o corpo não mexer em nada).
    func updateRows<S: Sequence>(_ ids: S, _ body: (inout MetadataRow) -> Void) where S.Element == MetadataRow.ID {
        let targets = positions(of: ids)
        guard !targets.isEmpty else { return }
        var next = rows
        for i in targets { body(&next[i]) }
        if targets.contains(where: { next[$0] != rows[$0] }) { rows = next }
    }

    func updateRow(_ id: MetadataRow.ID, _ body: (inout MetadataRow) -> Void) { updateRows([id], body) }

    private func scheduleQuery() {
        queryTask?.cancel()
        // Apagar o filtro vale na hora; digitar espera a pausa entre teclas.
        guard !query.isEmpty else { appliedQuery = ""; return }
        queryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            if self.appliedQuery != self.query { self.appliedQuery = self.query }
        }
    }

    private func scheduleColumnsSave() {
        columnsSaveTask?.cancel()
        // Arrastar uma coluna muda a largura várias vezes por segundo: grava só quando para.
        columnsSaveTask = Task { [self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(columnCustomization) {
                UserDefaults.standard.set(data, forKey: Self.columnsKey)
            }
        }
    }

    // MARK: Pasta

    func openIfNeeded(_ url: URL) {
        if folder == nil { open(url) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Abrir")
        panel.message = String(localized: "Escolha a pasta com as músicas para verificar")
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard confirmDiscard() else { return }
        cancelWork()
        cancelCoverTasks()
        folder = url
        reload()
    }

    func reload() {
        guard let folder else { return }
        loadToken &+= 1
        let token = loadToken
        isLoading = true
        message = nil
        Task {
            let urls = await Task.detached { FolderAnalyzer.audioFiles(in: folder) }.value
            let files = await FolderAnalyzer.analyze(urls)
            // As linhas (e as chaves de busca e ordenação de cada uma) são montadas fora da thread principal.
            let built = await Task.detached {
                let ignored = IgnoredIssuesStore.shared.all()
                return files.map { MetadataRow(file: $0, ignored: ignored[$0.url.path] ?? []) }
            }.value
            // Outra pasta (ou outra análise) começou enquanto esta lia: descarta.
            guard self.folder == folder, self.loadToken == token else { return }
            replaceRows(built)
            selection = []
            isLoading = false
            let problems = summary.withProblems
            message = rows.isEmpty ? String(localized: "Nenhuma música nesta pasta.")
                : String(localized: "\(rows.count) músicas analisadas · \(problems) com algo a corrigir")
        }
    }

    private func confirmDiscard() -> Bool {
        guard dirtyCount > 0 else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Descartar alterações não salvas?")
        alert.informativeText = String(localized: "\(dirtyCount) músicas têm alterações que ainda não foram gravadas.")
        alert.addButton(withTitle: String(localized: "Descartar"))
        alert.addButton(withTitle: String(localized: "Cancelar"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Edição manual

    struct FieldState { let common: String?; let edited: Bool; let distinct: [String] }

    /// Valor comum, edição e valores distintos de um campo na seleção, calculados uma vez por mudança.
    private func fieldState(_ field: String) -> FieldState {
        if let c = fieldCache, c.rows == rowsVersion, c.selection == selectionVersion, let hit = c.values[field] { return hit }
        let selected = selectedRows
        let values = Set(selected.map { $0.value(field) })
        let state = FieldState(common: values.count == 1 ? values.first : nil,
                               edited: selected.contains { $0.isEdited(field) },
                               distinct: values.filter { !$0.isEmpty }.sorted())
        var cached = fieldCache.flatMap { $0.rows == rowsVersion && $0.selection == selectionVersion ? $0.values : nil } ?? [:]
        cached[field] = state
        fieldCache = (rowsVersion, selectionVersion, cached)
        return state
    }

    /// Valor comum entre as linhas selecionadas (nil se diferem).
    func commonValue(_ field: String) -> String? { fieldState(field).common }

    func isEditedInSelection(_ field: String) -> Bool { fieldState(field).edited }

    /// Valores distintos de um campo nas linhas selecionadas (para o menu do campo).
    func distinctValues(_ field: String) -> [String] { fieldState(field).distinct }

    /// Chamado a cada tecla dos campos da barra lateral: só as linhas selecionadas são tocadas.
    func set(_ field: String, _ value: String) {
        updateRows(selection) { row in
            row.set(field, value)
            row.refreshStatus()
        }
    }

    func setCover(_ cover: CoverImage?) {
        updateRows(selection) { row in
            row.cover = cover
            row.refreshStatus()
        }
    }

    func chooseCoverFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.message = String(localized: "Escolha a imagem da capa (JPEG ou PNG)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setCoverData(try? Data(contentsOf: url))
    }

    func setCoverData(_ data: Data?) {
        guard let data, let mime = CoverArtClient.mimeType(of: data) else {
            message = String(localized: "A imagem precisa ser JPEG ou PNG.")
            return
        }
        setCover(CoverImage(data: data, mimeType: mime))
    }

    func setLyrics(_ lyrics: LyricsCandidate?, for id: MetadataRow.ID) {
        updateRow(id) { $0.setLyrics(lyrics) }
    }

    func revertSelection() {
        updateRows(selection) { row in
            row.edits = [:]; row.cover = nil; row.lyrics = nil; row.status = .idle
        }
    }

    // MARK: Busca

    /// Aplica uma correspondência a uma linha (respeitando a política) e busca a capa, se faltar.
    func use(_ candidate: MatchCandidate, for id: MetadataRow.ID) {
        guard let current = row(id) else { return }
        let policy = policy
        updateRow(id) { row in
            for (field, value) in MetadataFixer.fieldChanges(candidate, file: row.file, policy: policy) {
                row.set(field, value)
            }
            row.proposal = FixProposal(match: candidate, candidates: row.proposal?.candidates ?? [candidate],
                                       cover: row.proposal?.cover, lyrics: row.proposal?.lyrics)
            row.status = .ready
        }
        coverTasks[id]?.cancel()
        guard !current.file.hasCover || policy == .overwrite else { return }
        let fixer = fixer
        coverTasks[id] = Task { [weak self] in
            let cover = try? await fixer.cover(for: candidate)
            // Outra escolha (ou outra pasta) chegou antes: a capa desta não vale mais.
            guard let self, !Task.isCancelled, let cover else { return }
            self.coverTasks[id] = nil
            self.updateRow(id) { row in
                guard row.proposal?.match?.id == candidate.id else { return }
                row.cover = cover
                row.refreshStatus()
            }
        }
    }

    /// Busca automática: aplica sozinha o que tiver confiança alta; o resto fica para revisão.
    func autoFix(onlySelection: Bool) {
        let targets = onlySelection ? selectedRows : rows.filter { !$0.openIssues.isEmpty }
        guard !targets.isEmpty else { message = String(localized: "Nada a corrigir."); return }
        run(targets.map(\.id)) { model, fixer, row in
            let file = row.file
            let policy = model.policy
            let proposal = try await fixer.propose(for: file, wantCover: policy == .overwrite ? true : nil)
            return { row in
                row.proposal = proposal
                // A letra é conferida à parte (título, artista e duração no catálogo): entra mesmo se os
                // metadados ficarem para revisão.
                if let lyrics = proposal.lyrics, lyrics.text != nil,
                   !file.hasSidecarLyrics || (file.lyricsSynced == false && lyrics.isSynced) {
                    row.lyrics = lyrics
                    row.replaceLyrics = file.hasSidecarLyrics
                }
                guard let match = proposal.match else {
                    row.status = row.isDirty ? .ready : .notFound
                    return
                }
                if match.confidence >= MetadataFixer.autoApplyConfidence {
                    for (field, value) in MetadataFixer.fieldChanges(match, file: file, policy: policy) {
                        row.set(field, value)
                    }
                    if let cover = proposal.cover { row.cover = cover }
                    row.status = row.isDirty ? .ready : .idle
                } else {
                    row.status = .review
                }
            }
        }
    }

    /// Só candidatos (sem aplicar), para a escolha manual.
    func searchCandidates(for id: MetadataRow.ID) {
        run([id]) { _, fixer, row in
            let list = try await fixer.findMatches(for: row.file)
            return { row in
                var p = row.proposal ?? FixProposal()
                p.candidates = list
                if p.match == nil { p.match = list.first }
                row.proposal = p
                row.status = list.isEmpty ? .notFound : (row.isDirty ? .ready : .review)
            }
        }
    }

    func lyricsOptions(for row: MetadataRow) async -> [LyricsCandidate] {
        guard allowOnline() else { return [] }
        do { return try await fixer.lyricsOptions(for: row.file, match: row.proposal?.match) } catch {
            if !Task.isCancelled { message = String(localized: "Não foi possível buscar letras: \(Self.describe(error))") }
            return []
        }
    }

    /// Toda busca online passa por aqui: na primeira vez, pede o consentimento.
    func allowOnline() -> Bool {
        if OnlineConsent.ensure() { return true }
        message = String(localized: "Consultas online desligadas. Para ligar, abra Opções.")
        return false
    }

    /// Mudança que um passo da busca devolve para aplicar na linha (só se a busca ainda valer).
    typealias RowUpdate = (inout MetadataRow) -> Void

    private func run(_ ids: [MetadataRow.ID],
                     _ step: @escaping @MainActor (MetadataManagerModel, MetadataFixer, MetadataRow) async throws -> RowUpdate?) {
        guard allowOnline() else { return }
        cancelWork()
        let fixer = fixer
        let token = beginWork(total: ids.count)
        workIDs = ids
        searchRuns += 1
        work = Task { [weak self] in
            for (n, id) in ids.enumerated() {
                guard let self, self.isCurrent(token) else { return }
                if let row = self.row(id) {
                    self.updateRow(id) { $0.status = .searching }
                    do {
                        let update = try await step(self, fixer, row)
                        // Parada ou trocada por outra busca durante a espera: não escreve nada.
                        guard self.isCurrent(token) else { return }
                        if let update { self.updateRow(id, update) }
                    } catch {
                        guard self.isCurrent(token) else { return }
                        self.updateRow(id) { $0.status = .failed(Self.describe(error)) }
                    }
                }
                self.progress = (n + 1, ids.count)
            }
            guard let self, self.isCurrent(token) else { return }
            self.finishWork()
        }
    }

    /// Começa uma tarefa nova (a anterior perde a vez) e mostra o progresso.
    func beginWork(total: Int) -> Int {
        workToken &+= 1
        progress = (0, total)
        return workToken
    }

    /// A tarefa `token` ainda é a atual e não foi cancelada.
    func isCurrent(_ token: Int) -> Bool { !Task.isCancelled && workToken == token }

    /// Fecha a tarefa `token`, se ainda for a atual.
    func endWork(_ token: Int) {
        guard workToken == token else { return }
        work = nil
        progress = nil
    }

    func cancelWork() {
        work?.cancel()
        work = nil
        workToken &+= 1
        progress = nil
        let searching = rows.filter { $0.status == .searching }.map(\.id)
        updateRows(searching) { $0.status = .idle }
    }

    private func finishWork() {
        work = nil
        progress = nil
        let ready = dirtyCount
        let review = rows.reduce(0) { $0 + ($1.status == .review ? 1 : 0) }
        let lyrics = rows.reduce(0) { $0 + ($1.lyrics?.text != nil ? 1 : 0) }
        message = String(localized: "\(ready) prontas para salvar · \(lyrics) letras encontradas")
            + (review > 0 ? String(localized: " · \(review) para revisar (confiança baixa)") : "")
        // Resumo só para buscas em lote: numa música só, a própria linha e o painel já mostram o resultado
        // (e um resumo por cima da janela de resultados fazia ela fechar, reabrir e buscar de novo, sem fim).
        let searched = positions(of: Set(workIDs)).map { rows[$0] }
        if searched.count > 1 { report = SearchReport(searched) }
        else if let only = searched.first {
            message = only.status == .notFound ? String(localized: "Nada encontrado para \(only.fileName).")
                : only.isDirty ? String(localized: "Dados encontrados para \(only.fileName) — confira e salve.") : message
        }
    }

    /// Fecha a lista da última busca (o painel de cards do rodapé).
    func clearWork() { if !isBusy { workIDs = [] } }

    /// Linhas da última busca, na ordem da busca (painel de cards).
    var workRows: [MetadataRow] { workIDs.compactMap { row($0) } }

    /// Letra escrita à mão (vira um .lrc estático, ou sincronizado se tiver marcas [mm:ss]).
    func setManualLyrics(_ text: String, for id: MetadataRow.ID) {
        guard let current = row(id) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { setLyrics(nil, for: id); return }
        let synced = trimmed.range(of: #"\[\d{1,2}:\d{2}"#, options: .regularExpression) != nil
        setLyrics(LyricsCandidate(id: "manual", title: current.value("title"), artist: current.value("artist"),
                                  duration: current.file.duration, synced: synced ? trimmed : nil, plain: synced ? nil : trimmed),
                  for: id)
    }

    /// Busca da seleção conforme os interruptores do painel: dados principais e/ou letra.
    func searchSelection(data: Bool, lyrics: Bool) {
        if data { autoFix(onlySelection: true) }
        if lyrics && !data { fetchLyrics(onlySelection: true) }
    }

    // MARK: Letras em lote

    /// Só letras (catálogo online), para quem não tem letra ou só tem a estática.
    func fetchLyrics(onlySelection: Bool) {
        let targets = onlySelection ? selectedRows : rows.filter { $0.file.lyricsSynced != true }
        guard !targets.isEmpty else { message = String(localized: "Todas já têm letra sincronizada."); return }
        let client = LyricsService.standard()
        run(targets.map(\.id)) { _, _, row in
            let q = MetadataFixer.query(for: row.file)
            let title = row.value("title").isEmpty ? q.title : row.value("title")
            let artist = row.value("artist").isEmpty ? q.artist : row.value("artist")
            let found = try await client.best(title: title, artist: artist, album: row.value("album").isEmpty ? nil : row.value("album"),
                                              duration: row.file.duration, syncedOnly: row.file.hasLyrics)
            return { row in
                if let found, found.text != nil {
                    row.setLyrics(found)
                } else if row.isDirty {
                    row.refreshStatus()
                } else {
                    row.status = .notFound
                }
            }
        }
    }

    // MARK: Rodapé

    /// "3 (12:04 | 48,2 MB)   12 (1:02:10 | 190 MB)": seleção e total, como o rodapé do Mp3tag.
    var footer: String {
        let total: String
        if let c = totalCache, c.rows == rowsVersion { total = c.value } else {
            total = Self.sum(rows)
            totalCache = (rowsVersion, total)
        }
        return "\(Self.sum(selectedRows))     \(total)"
    }

    private static func sum(_ rows: [MetadataRow]) -> String {
        let seconds = Int(rows.compactMap(\.file.duration).reduce(0, +))
        let time = seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
        let size = ByteCountFormatter.string(fromByteCount: rows.reduce(0) { $0 + $1.file.size }, countStyle: .file)
        return "\(rows.count) (\(time) | \(size))"
    }

    // MARK: Busca por álbum (como a Fonte de Etiquetas do Mp3tag)

    let musicBrainz = MusicBrainzClient()
    let coverArt = CoverArtClient()

    /// Artista e álbum para começar a busca: o que as selecionadas têm em comum, senão o nome da pasta.
    var albumQuery: (artist: String, album: String) {
        let rows = selectedRows.isEmpty ? rows : selectedRows
        func common(_ f: String) -> String? {
            let values = Set(rows.map { $0.value(f) }.filter { !$0.isEmpty })
            return values.count == 1 ? values.first : nil
        }
        let guess = rows.first.map { MetadataFixer.query(for: $0.file) }
        let artist = common("albumArtist") ?? common("artist") ?? (guess?.artist ?? "")
        let album = common("album") ?? rows.first?.proposal?.match?.album ?? ""
        return (artist, album)
    }

    /// Álbum desconhecido: descobre pela música (título + artista) na busca do iTunes.
    func suggestAlbum() async -> String? {
        guard OnlineConsent.isGranted, OnlineServices.isOn(.albumHint) else { return nil }
        guard let row = (selectedRows.isEmpty ? rows : selectedRows).first else { return nil }
        let q = MetadataFixer.query(for: row.file)
        return try? await ITunesHintClient().albumHint(title: q.title, artist: q.artist, duration: row.file.duration)?.album
    }

    /// Linhas que a busca por álbum vai preencher (seleção; senão todas as visíveis).
    var albumTargets: [MetadataRow] { selectedRows.isEmpty ? visibleRows : selectedRows }

    /// Grava nas linhas (pendente, até salvar) os campos marcados do álbum e de cada faixa pareada, e a capa.
    func applyRelease(_ release: ReleaseDetail, pairs: [MetadataRow.ID: Int], fields: Set<String>, cover: CoverImage?) {
        let valid = pairs.filter { release.tracks.indices.contains($0.value) }
        let count = positions(of: valid.keys).count
        updateRows(valid.keys) { row in
            guard let trackIndex = valid[row.id] else { return }
            let track = release.tracks[trackIndex]
            let values = release.albumFields.merging(ReleaseDetail.trackFields(track)) { $1 }
            for (field, value) in values where fields.contains(field) { row.set(field, value) }
            if let cover { row.cover = cover }
            row.proposal = FixProposal(match: MatchCandidate(
                source: .musicBrainz, recordingID: track.recordingID ?? release.id,
                releaseID: release.id, releaseGroupID: release.releaseGroupID,
                title: track.title, artist: track.artist,
                album: release.title, confidence: 1))
            row.refreshStatus()
        }
        message = String(localized: "\(count) músicas preenchidas com “\(release.title)” — confira e salve")
    }

    // MARK: Capa na pasta e histórico (a gravação fica em MetadataManagerModel+Save)

    enum CoverSaveMode: String, CaseIterable, Identifiable, Sendable {
        case embed, folder, both
        var id: String { rawValue }
        var title: String {
            switch self {
            case .embed: String(localized: "Embutir no arquivo de música")
            case .folder: String(localized: "Salvar como cover.jpg na pasta")
            case .both: String(localized: "Os dois")
            }
        }
    }

    static let coverSaveKey = "metadata.coverSave"
    @Published var coverSaveMode = CoverSaveMode(rawValue: UserDefaults.standard.string(forKey: MetadataManagerModel.coverSaveKey) ?? "") ?? .embed {
        didSet { UserDefaults.standard.set(coverSaveMode.rawValue, forKey: Self.coverSaveKey) }
    }

    var history: SaveHistoryStore { SaveHistoryStore.shared }
    /// Lotes gravados, mais recente primeiro (atualizado pelas tarefas de gravar e desfazer).
    @Published var batches: [SaveBatch] = []

    /// A janela fechou: para a busca (os resultados não teriam onde aparecer).
    func windowClosed() {
        queryTask?.cancel()
        cancelWork()
        cancelCoverTasks()
    }

    private func cancelCoverTasks() {
        for task in coverTasks.values { task.cancel() }
        coverTasks = [:]
    }

    nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case TagWriterError.unsupportedFormat: String(localized: "Formato sem gravação de tags")
        case TagWriterError.insufficientSpace: String(localized: "Sem espaço em disco")
        case TagWriterError.verificationFailed: String(localized: "Gravação não conferiu; arquivo mantido")
        case LyricsFileWriter.WriteError.alreadyExists: String(localized: "Já existe um .lrc")
        case FixerNetworkError.rateLimited: String(localized: "Serviço ocupado, tente de novo")
        case FixerNetworkError.notFound: String(localized: "Não encontrada")
        case is URLError: String(localized: "Sem conexão")
        default: String(localized: "Erro ao gravar")
        }
    }
}

/// Problemas abertos na pasta: quantas músicas têm cada um e quantas têm algum.
struct CollectionCounts: Equatable {
    var issues: [FixerIssue: Int] = [:]
    var withProblems = 0

    func count(_ issue: FixerIssue) -> Int { issues[issue] ?? 0 }
}

/// O que a última busca conseguiu: completas, parciais (com o que faltou) e sem nada.
struct SearchReport: Identifiable {
    struct Partial: Identifiable { let id: String; let name: String; let found: [String]; let missing: [String] }

    let id = UUID()
    let total: Int
    let complete: Int
    let partial: [Partial]
    let notFound: [String]
    let review: Int
    /// "Letra: 4 · Capa: 2" — o que mais faltou, somando as parciais.
    let missingTotals: [(String, Int)]

    init(_ rows: [MetadataRow]) {
        total = rows.count
        complete = rows.filter { $0.isComplete && $0.status != .notFound }.count
        partial = rows.filter { !$0.isComplete && !$0.foundItems.isEmpty }
            .map { Partial(id: $0.id, name: $0.fileName, found: $0.foundItems, missing: $0.missingEssentials) }
        notFound = rows.filter { $0.status == .notFound || ($0.foundItems.isEmpty && !$0.isComplete) }.map(\.fileName)
        review = rows.filter { $0.status == .review }.count
        var counts: [String: Int] = [:]
        for p in partial { for m in p.missing { counts[m, default: 0] += 1 } }
        missingTotals = counts.sorted { $0.value > $1.value }
    }
}
