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
    @Published var rows: [MetadataRow] = []
    @Published var selection: Set<MetadataRow.ID> = []
    @Published var filter: MetadataFilter = .all
    @Published var query = ""
    /// Colunas visíveis/ordem/largura (clique direito no cabeçalho), lembradas entre aberturas.
    @Published var columnCustomization: TableColumnCustomization<MetadataRow> = MetadataManagerModel.loadColumns() {
        didSet {
            if let data = try? JSONEncoder().encode(columnCustomization) {
                UserDefaults.standard.set(data, forKey: Self.columnsKey)
            }
        }
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

    @Published var sortOrder: [KeyPathComparator<MetadataRow>] = [KeyPathComparator(\.sortFile)]
    @Published private(set) var isLoading = false
    @Published private(set) var progress: (done: Int, total: Int)?
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
    private let writer: TagWriter?
    private var work: Task<Void, Never>?

    init(database: LibraryDatabase?) {
        writer = database.map { TagWriter(database: $0, backups: BackupStore()) }
        policy = FillPolicy(rawValue: UserDefaults.standard.string(forKey: Self.policyDefaults) ?? "") ?? .missingOnly
        acoustIDKey = UserDefaults.standard.string(forKey: Self.acoustIDKeyDefaults) ?? ""
    }

    var fpcalcFound: Bool { AcoustIDClient.fpcalcPath() != nil }
    var isBusy: Bool { work != nil }

    private var fixer: MetadataFixer {
        let key = acoustIDKey.trimmingCharacters(in: .whitespaces)
        return MetadataFixer(acoustID: key.isEmpty ? nil : AcoustIDClient(apiKey: key))
    }

    // MARK: Lista

    var visibleRows: [MetadataRow] {
        let q = TextMatch.normalize(query)
        let filtered = rows.filter { row in
            filter.includes(row) && (q.isEmpty || [row.fileName, row.value("title"), row.value("artist"),
                                                   row.value("album")].contains { TextMatch.normalize($0).contains(q) })
        }
        return filtered.sorted(using: sortOrder)
    }

    var selectedRows: [MetadataRow] { rows.filter { selection.contains($0.id) } }
    var dirtyCount: Int { rows.filter(\.isDirty).count }

    func index(of id: MetadataRow.ID) -> Int? { rows.firstIndex { $0.id == id } }

    // MARK: Pasta

    func openIfNeeded(_ url: URL) {
        if folder == nil { open(url) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Abrir"
        panel.message = "Escolha a pasta com as músicas para verificar"
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard confirmDiscard() else { return }
        cancelWork()
        folder = url
        reload()
    }

    func reload() {
        guard let folder else { return }
        isLoading = true
        message = nil
        Task {
            let urls = await Task.detached { FolderAnalyzer.audioFiles(in: folder) }.value
            let files = await FolderAnalyzer.analyze(urls)
            guard self.folder == folder else { return }
            let ignored = IgnoredIssuesStore.shared.all()
            rows = files.map { MetadataRow(file: $0, ignored: ignored[$0.url.path] ?? []) }
            selection = []
            isLoading = false
            let problems = rows.filter { !$0.openIssues.isEmpty }.count
            message = rows.isEmpty ? "Nenhuma música nesta pasta."
                : "\(rows.count) músicas analisadas · \(problems) com algo a corrigir"
        }
    }

    private func confirmDiscard() -> Bool {
        guard dirtyCount > 0 else { return true }
        let alert = NSAlert()
        alert.messageText = "Descartar alterações não salvas?"
        alert.informativeText = "\(dirtyCount) músicas têm alterações que ainda não foram gravadas."
        alert.addButton(withTitle: "Descartar")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Edição manual

    /// Valor comum entre as linhas selecionadas (nil se diferem).
    func commonValue(_ field: String) -> String? {
        let values = Set(selectedRows.map { $0.value(field) })
        return values.count == 1 ? values.first : nil
    }

    func isEditedInSelection(_ field: String) -> Bool { selectedRows.contains { $0.isEdited(field) } }

    func set(_ field: String, _ value: String) {
        for id in selection { if let i = index(of: id) { rows[i].set(field, value); refreshStatus(i) } }
    }

    func setCover(_ cover: CoverImage?) {
        for id in selection { if let i = index(of: id) { rows[i].cover = cover; refreshStatus(i) } }
    }

    func chooseCoverFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.message = "Escolha a imagem da capa (JPEG ou PNG)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setCoverData(try? Data(contentsOf: url))
    }

    func setCoverData(_ data: Data?) {
        guard let data, let mime = CoverArtClient.mimeType(of: data) else {
            message = "A imagem precisa ser JPEG ou PNG."
            return
        }
        setCover(CoverImage(data: data, mimeType: mime))
    }

    func setLyrics(_ lyrics: LyricsCandidate?, for id: MetadataRow.ID) {
        guard let i = index(of: id) else { return }
        rows[i].lyrics = lyrics
        rows[i].replaceLyrics = rows[i].file.hasSidecarLyrics
        refreshStatus(i)
    }

    func revertSelection() {
        for id in selection {
            guard let i = index(of: id) else { continue }
            rows[i].edits = [:]; rows[i].cover = nil; rows[i].lyrics = nil; rows[i].status = .idle
        }
    }

    private func refreshStatus(_ i: Int) {
        if rows[i].isDirty { rows[i].status = .ready } else if rows[i].status == .ready { rows[i].status = .idle }
    }

    // MARK: Busca

    /// Aplica uma correspondência a uma linha (respeitando a política) e busca a capa, se faltar.
    func use(_ candidate: MatchCandidate, for id: MetadataRow.ID) {
        guard let i = index(of: id) else { return }
        for (field, value) in MetadataFixer.fieldChanges(candidate, file: rows[i].file, policy: policy) {
            rows[i].set(field, value)
        }
        rows[i].proposal = FixProposal(match: candidate, candidates: rows[i].proposal?.candidates ?? [candidate],
                                       cover: rows[i].proposal?.cover, lyrics: rows[i].proposal?.lyrics)
        rows[i].status = .ready
        guard !rows[i].file.hasCover || policy == .overwrite else { return }
        let fixer = fixer
        Task {
            let cover = try? await fixer.cover(for: candidate)
            if let cover, let j = index(of: id) { rows[j].cover = cover; refreshStatus(j) }
        }
    }

    /// Busca automática: aplica sozinha o que tiver confiança alta; o resto fica para revisão.
    func autoFix(onlySelection: Bool) {
        let targets = (onlySelection ? selectedRows : rows).filter { onlySelection || !$0.openIssues.isEmpty }
        guard !targets.isEmpty else { message = "Nada a corrigir."; return }
        run(targets.map(\.id)) { model, fixer, id in
            guard let file = model.rows.first(where: { $0.id == id })?.file else { return }
            let policy = model.policy
            let proposal = try await fixer.propose(for: file, wantCover: policy == .overwrite ? true : nil)
            guard let i = model.index(of: id) else { return }
            model.rows[i].proposal = proposal
            // A letra é conferida à parte (título, artista e duração no catálogo): entra mesmo se os
            // metadados ficarem para revisão.
            if let lyrics = proposal.lyrics, lyrics.text != nil,
               !file.hasSidecarLyrics || (file.lyricsSynced == false && lyrics.isSynced) {
                model.rows[i].lyrics = lyrics
                model.rows[i].replaceLyrics = file.hasSidecarLyrics
            }
            guard let match = proposal.match else {
                model.rows[i].status = model.rows[i].isDirty ? .ready : .notFound
                return
            }
            if match.confidence >= MetadataFixer.autoApplyConfidence {
                for (field, value) in MetadataFixer.fieldChanges(match, file: file, policy: policy) {
                    model.rows[i].set(field, value)
                }
                if let cover = proposal.cover { model.rows[i].cover = cover }
                model.rows[i].status = model.rows[i].isDirty ? .ready : .idle
            } else {
                model.rows[i].status = .review
            }
        }
    }

    /// Só candidatos (sem aplicar), para a escolha manual.
    func searchCandidates(for id: MetadataRow.ID) {
        run([id]) { model, fixer, id in
            guard let file = model.rows.first(where: { $0.id == id })?.file else { return }
            let list = try await fixer.findMatches(for: file)
            guard let i = model.index(of: id) else { return }
            var p = model.rows[i].proposal ?? FixProposal()
            p.candidates = list
            if p.match == nil { p.match = list.first }
            model.rows[i].proposal = p
            model.rows[i].status = list.isEmpty ? .notFound : (model.rows[i].isDirty ? .ready : .review)
        }
    }

    func lyricsOptions(for row: MetadataRow) async -> [LyricsCandidate] {
        guard allowOnline() else { return [] }
        do { return try await fixer.lyricsOptions(for: row.file, match: row.proposal?.match) } catch {
            message = "Não foi possível buscar letras: \(Self.describe(error))"
            return []
        }
    }

    /// Toda busca online passa por aqui: na primeira vez, pede o consentimento.
    func allowOnline() -> Bool {
        if OnlineConsent.ensure() { return true }
        message = "Consultas online desligadas. Para ligar, abra Opções."
        return false
    }

    private func run(_ ids: [MetadataRow.ID],
                     _ step: @escaping @MainActor (MetadataManagerModel, MetadataFixer, MetadataRow.ID) async throws -> Void) {
        guard allowOnline() else { return }
        cancelWork()
        let fixer = fixer
        progress = (0, ids.count)
        workIDs = ids
        work = Task { [weak self] in
            for (n, id) in ids.enumerated() {
                guard let self, !Task.isCancelled else { break }
                if let i = self.index(of: id) { self.rows[i].status = .searching }
                do { try await step(self, fixer, id) } catch {
                    if let i = self.index(of: id) { self.rows[i].status = .failed(Self.describe(error)) }
                }
                self.progress = (n + 1, ids.count)
            }
            self?.finishWork()
        }
    }

    func cancelWork() {
        work?.cancel()
        work = nil
        progress = nil
        for i in rows.indices where rows[i].status == .searching { rows[i].status = .idle }
    }

    private func finishWork() {
        work = nil
        progress = nil
        let ready = rows.filter(\.isDirty).count
        let review = rows.filter { $0.status == .review }.count
        let lyrics = rows.filter { $0.lyrics?.text != nil }.count
        message = "\(ready) prontas para salvar · \(lyrics) letras encontradas" + (review > 0 ? " · \(review) para revisar (confiança baixa)" : "")
        // Resumo só para buscas em lote: numa música só, a própria linha e o painel já mostram o resultado
        // (e um resumo por cima da janela de resultados fazia ela fechar, reabrir e buscar de novo, sem fim).
        let searched = rows.filter { workIDs.contains($0.id) }
        if searched.count > 1 { report = SearchReport(searched) }
        else if let only = searched.first {
            message = only.status == .notFound ? "Nada encontrado para \(only.fileName)."
                : only.isDirty ? "Dados encontrados para \(only.fileName) — confira e salve." : message
        }
    }

    /// Fecha a lista da última busca (o painel de cards do rodapé).
    func clearWork() { if !isBusy { workIDs = [] } }

    /// Letra escrita à mão (vira um .lrc estático, ou sincronizado se tiver marcas [mm:ss]).
    func setManualLyrics(_ text: String, for id: MetadataRow.ID) {
        guard let i = index(of: id) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { setLyrics(nil, for: id); return }
        let synced = trimmed.range(of: #"\[\d{1,2}:\d{2}"#, options: .regularExpression) != nil
        setLyrics(LyricsCandidate(id: "manual", title: rows[i].value("title"), artist: rows[i].value("artist"),
                                  duration: rows[i].file.duration, synced: synced ? trimmed : nil, plain: synced ? nil : trimmed),
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
        let targets = (onlySelection ? selectedRows : rows).filter { onlySelection || $0.file.lyricsSynced != true }
        guard !targets.isEmpty else { message = "Todas já têm letra sincronizada."; return }
        let client = LyricsService.standard()
        run(targets.map(\.id)) { model, _, id in
            guard let row = model.rows.first(where: { $0.id == id }) else { return }
            let q = MetadataFixer.query(for: row.file)
            let title = row.value("title").isEmpty ? q.title : row.value("title")
            let artist = row.value("artist").isEmpty ? q.artist : row.value("artist")
            let found = try await client.best(title: title, artist: artist, album: row.value("album").isEmpty ? nil : row.value("album"),
                                              duration: row.file.duration, syncedOnly: row.file.hasLyrics)
            guard let i = model.index(of: id) else { return }
            if let found, found.text != nil {
                model.setLyrics(found, for: id)
            } else if !model.rows[i].isDirty {
                model.rows[i].status = .notFound
            }
        }
    }

    // MARK: Rodapé

    /// "3 (12:04 | 48,2 MB)   12 (1:02:10 | 190 MB)": seleção e total, como o rodapé do Mp3tag.
    var footer: String {
        func sum(_ rows: [MetadataRow]) -> String {
            let seconds = Int(rows.compactMap(\.file.duration).reduce(0, +))
            let time = seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                : String(format: "%d:%02d", seconds / 60, seconds % 60)
            let size = ByteCountFormatter.string(fromByteCount: rows.reduce(0) { $0 + $1.file.size }, countStyle: .file)
            return "\(rows.count) (\(time) | \(size))"
        }
        return "\(sum(selectedRows))     \(sum(rows))"
    }

    /// Valores distintos de um campo nas linhas selecionadas (para o menu do campo).
    func distinctValues(_ field: String) -> [String] {
        Array(Set(selectedRows.map { $0.value(field) }.filter { !$0.isEmpty })).sorted()
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
        var count = 0
        for (id, trackIndex) in pairs {
            guard let i = index(of: id), release.tracks.indices.contains(trackIndex) else { continue }
            let values = release.albumFields.merging(ReleaseDetail.trackFields(release.tracks[trackIndex])) { $1 }
            for (field, value) in values where fields.contains(field) { rows[i].set(field, value) }
            if let cover { rows[i].cover = cover }
            rows[i].proposal = FixProposal(match: MatchCandidate(
                source: .musicBrainz, recordingID: release.tracks[trackIndex].recordingID ?? release.id,
                releaseID: release.id, releaseGroupID: release.releaseGroupID,
                title: release.tracks[trackIndex].title, artist: release.tracks[trackIndex].artist,
                album: release.title, confidence: 1))
            refreshStatus(i)
            count += 1
        }
        message = "\(count) músicas preenchidas com “\(release.title)” — confira e salve"
    }

    // MARK: Gravação

    func save(onlySelection: Bool) {
        guard let writer else { message = "Biblioteca indisponível: não é possível gravar."; return }
        let targets = (onlySelection ? selectedRows : rows).filter(\.isDirty)
        guard !targets.isEmpty else { message = "Nenhuma alteração para salvar."; return }
        var saved = 0, failed = 0
        var items: [SaveBatch.Item] = []
        for row in targets {
            guard let i = index(of: row.id) else { continue }
            var item = SaveBatch.Item(path: row.url.path)
            do {
                let mode = coverSaveMode
                var changes = row.tagChanges
                if mode == .folder { changes.cover = nil }
                if !changes.isEmpty {
                    guard row.file.isWritable else { throw TagWriterError.unsupportedFormat }
                    item.journalID = try writer.apply(changes, url: row.url).id
                }
                // Capa também (ou só) como imagem na pasta, sem trocar uma que já exista.
                if let cover = row.cover, mode != .embed, let created = Self.writeFolderCover(cover, beside: row.url) {
                    item.createdFiles.append(created.path)
                }
                if let text = row.lyrics?.text {
                    let lrc = row.file.lyricsURL
                    let backup = row.replaceLyrics ? try history.backupLyrics(of: lrc) : nil
                    _ = try LyricsFileWriter.write(text, for: row.url, replace: row.replaceLyrics)
                    item.lyricsBackup = backup
                    item.wroteLyrics = true
                }
                var fresh = FolderAnalyzer.read(row.url)
                fresh.duplicateGroup = row.file.duplicateGroup
                if fresh.duplicateGroup != nil { fresh.issues.insert(.duplicate) }
                rows[i] = MetadataRow(file: fresh, proposal: row.proposal, status: .saved, ignored: row.ignored)
                saved += 1
            } catch {
                rows[i].status = .failed(Self.describe(error))
                failed += 1
            }
            if item.journalID != nil || item.wroteLyrics || !item.createdFiles.isEmpty { items.append(item) }
        }
        if !items.isEmpty {
            try? history.add(SaveBatch(folder: folder?.path ?? "", items: items))
            refreshHistory()
        }
        message = "\(saved) músicas salvas" + (failed > 0 ? " · \(failed) com erro" : "")
            + " · dá para desfazer em Histórico (⌘Z)"
    }

    // MARK: Problemas ignorados

    /// Ignora problemas nas linhas (todos os abertos, ou só `issue`); fica salvo para as próximas análises.
    func ignore(_ issue: FixerIssue?, ids: Set<MetadataRow.ID>) {
        for id in ids {
            guard let i = index(of: id) else { continue }
            rows[i].ignored.formUnion(issue.map { [$0] } ?? Set(rows[i].openIssues))
            try? IgnoredIssuesStore.shared.set(rows[i].ignored, for: rows[i].url.path)
        }
    }

    func unignore(ids: Set<MetadataRow.ID>) {
        for id in ids {
            guard let i = index(of: id) else { continue }
            rows[i].ignored = []
            try? IgnoredIssuesStore.shared.set([], for: rows[i].url.path)
        }
    }

    // MARK: Duplicadas

    /// Manda os arquivos para a Lixeira (com o .lrc ao lado, se houver) e tira da lista.
    func trash(paths: Set<String>) {
        var moved = 0
        var failed: [String] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                let lrc = url.deletingPathExtension().appendingPathExtension("lrc")
                if FileManager.default.fileExists(atPath: lrc.path) { try? FileManager.default.trashItem(at: lrc, resultingItemURL: nil) }
                moved += 1
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        let remaining = rows.filter { !paths.contains($0.url.path) || failed.contains($0.fileName) }
        let regrouped = FolderAnalyzer.markDuplicates(remaining.map(\.file))
        rows = zip(remaining, regrouped).map { old, file in
            var row = old
            row.file = file
            return row
        }
        selection.subtract(paths)
        message = "\(moved) arquivo(s) na Lixeira" + (failed.isEmpty ? "" : " · não deu: \(failed.joined(separator: ", "))")
    }

    // MARK: Capa na pasta

    enum CoverSaveMode: String, CaseIterable, Identifiable {
        case embed, folder, both
        var id: String { rawValue }
        var title: String {
            switch self {
            case .embed: "Embutir no arquivo de música"
            case .folder: "Salvar como cover.jpg na pasta"
            case .both: "Os dois"
            }
        }
    }

    static let coverSaveKey = "metadata.coverSave"
    @Published var coverSaveMode = CoverSaveMode(rawValue: UserDefaults.standard.string(forKey: MetadataManagerModel.coverSaveKey) ?? "") ?? .embed {
        didSet { UserDefaults.standard.set(coverSaveMode.rawValue, forKey: Self.coverSaveKey) }
    }

    /// Grava cover.jpg/png na pasta da música se ainda não há capa solta lá. Devolve o arquivo criado.
    static func writeFolderCover(_ cover: CoverImage, beside audio: URL) -> URL? {
        let folder = audio.deletingLastPathComponent()
        FolderCover.invalidate(folder)
        guard FolderCover.url(for: audio) == nil else { return nil }
        let dest = folder.appendingPathComponent(cover.mimeType == "image/png" ? "cover.png" : "cover.jpg")
        guard !FileManager.default.fileExists(atPath: dest.path), (try? cover.data.write(to: dest, options: .withoutOverwriting)) != nil
        else { return nil }
        FolderCover.invalidate(folder)
        return dest
    }

    // MARK: Histórico e desfazer

    let history = SaveHistoryStore.shared
    @Published private(set) var batches: [SaveBatch] = []

    func refreshHistory() { batches = history.batches() }

    var lastUndoable: SaveBatch? { batches.first { !$0.undone } }

    /// Desfaz um lote inteiro e relê os arquivos afetados que estão na lista.
    func undo(_ batch: SaveBatch) {
        guard let writer else { return }
        let result = BatchUndo.undo(batch, writer: writer)
        if result.failed.isEmpty || result.restored > 0 { try? history.markUndone(batch.id) }
        refreshHistory()
        let paths = Set(batch.items.map(\.path))
        for i in rows.indices where paths.contains(rows[i].url.path) {
            var fresh = FolderAnalyzer.read(rows[i].url)
            fresh.duplicateGroup = rows[i].file.duplicateGroup
            if fresh.duplicateGroup != nil { fresh.issues.insert(.duplicate) }
            rows[i] = MetadataRow(file: fresh, ignored: rows[i].ignored)
        }
        message = "\(result.restored) músicas voltaram ao que eram"
            + (result.failed.isEmpty ? "" : " · não deu para desfazer: \(result.failed.joined(separator: ", ")) (alterado depois por outro programa?)")
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case TagWriterError.unsupportedFormat: "Formato sem gravação de tags"
        case TagWriterError.insufficientSpace: "Sem espaço em disco"
        case TagWriterError.verificationFailed: "Gravação não conferiu; arquivo mantido"
        case LyricsFileWriter.WriteError.alreadyExists: "Já existe um .lrc"
        case FixerNetworkError.rateLimited: "Serviço ocupado, tente de novo"
        case FixerNetworkError.notFound: "Não encontrada"
        case is URLError: "Sem conexão"
        default: "Erro ao gravar"
        }
    }
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
