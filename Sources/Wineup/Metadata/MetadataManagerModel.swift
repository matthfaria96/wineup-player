import AppKit
import Foundation
import WineupLibrary

/// Estado do gerenciador de metadados: pasta, análise, busca nas bases e gravação segura.
@MainActor
final class MetadataManagerModel: ObservableObject {
    static let acoustIDKeyDefaults = "metadata.acoustIDKey"
    static let policyDefaults = "metadata.fillPolicy"
    static let shazamDefaults = "metadata.useShazam"

    @Published private(set) var folder: URL?
    @Published var rows: [MetadataRow] = []
    @Published var selection: Set<MetadataRow.ID> = []
    @Published var filter: MetadataFilter = .all
    @Published var query = ""
    @Published private(set) var isLoading = false
    @Published private(set) var progress: (done: Int, total: Int)?
    @Published var message: String?
    @Published var policy: FillPolicy {
        didSet { UserDefaults.standard.set(policy.rawValue, forKey: Self.policyDefaults) }
    }
    @Published var useShazam: Bool {
        didSet { UserDefaults.standard.set(useShazam, forKey: Self.shazamDefaults) }
    }
    @Published private(set) var shazamStatus: ShazamRecognizer.Availability = .unknown
    @Published var acoustIDKey: String {
        didSet { UserDefaults.standard.set(acoustIDKey, forKey: Self.acoustIDKeyDefaults) }
    }

    /// Pausa o player principal antes da prévia do visualizador de letra.
    var pauseMainPlayback: (() -> Void)?
    private let writer: TagWriter?
    private var work: Task<Void, Never>?

    init(database: LibraryDatabase?) {
        writer = database.map { TagWriter(database: $0, backups: BackupStore()) }
        policy = FillPolicy(rawValue: UserDefaults.standard.string(forKey: Self.policyDefaults) ?? "") ?? .missingOnly
        acoustIDKey = UserDefaults.standard.string(forKey: Self.acoustIDKeyDefaults) ?? ""
        useShazam = UserDefaults.standard.object(forKey: Self.shazamDefaults) as? Bool ?? true
    }

    func refreshShazamStatus() {
        Task { shazamStatus = await ShazamRecognizer.shared.availability }
    }

    var fpcalcFound: Bool { AcoustIDClient.fpcalcPath() != nil }
    var isBusy: Bool { work != nil }

    private var fixer: MetadataFixer {
        let key = acoustIDKey.trimmingCharacters(in: .whitespaces)
        return MetadataFixer(acoustID: key.isEmpty ? nil : AcoustIDClient(apiKey: key),
                             shazam: useShazam ? ShazamRecognizer.shared : nil)
    }

    // MARK: Lista

    var visibleRows: [MetadataRow] {
        let q = TextMatch.normalize(query)
        return rows.filter { row in
            filter.includes(row) && (q.isEmpty || [row.fileName, row.value("title"), row.value("artist"),
                                                   row.value("album")].contains { TextMatch.normalize($0).contains(q) })
        }
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
            rows = files.map { MetadataRow(file: $0) }
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
            // A letra é conferida à parte (título, artista e duração no LRCLIB): entra mesmo se os
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
        do { return try await fixer.lyricsOptions(for: row.file, match: row.proposal?.match) } catch {
            message = "Não foi possível buscar letras: \(Self.describe(error))"
            return []
        }
    }

    private func run(_ ids: [MetadataRow.ID],
                     _ step: @escaping @MainActor (MetadataManagerModel, MetadataFixer, MetadataRow.ID) async throws -> Void) {
        cancelWork()
        let fixer = fixer
        progress = (0, ids.count)
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
        refreshShazamStatus()
        work = nil
        progress = nil
        let ready = rows.filter(\.isDirty).count
        let review = rows.filter { $0.status == .review }.count
        let lyrics = rows.filter { $0.lyrics?.text != nil }.count
        message = "\(ready) prontas para salvar · \(lyrics) letras encontradas" + (review > 0 ? " · \(review) para revisar (confiança baixa)" : "")
    }

    // MARK: Gravação

    func save(onlySelection: Bool) {
        guard let writer else { message = "Biblioteca indisponível: não é possível gravar."; return }
        let targets = (onlySelection ? selectedRows : rows).filter(\.isDirty)
        guard !targets.isEmpty else { message = "Nenhuma alteração para salvar."; return }
        var saved = 0, failed = 0
        for row in targets {
            guard let i = index(of: row.id) else { continue }
            do {
                if row.hasTagChanges {
                    guard row.file.isWritable else { throw TagWriterError.unsupportedFormat }
                    try writer.apply(row.tagChanges, url: row.url)
                }
                if let text = row.lyrics?.text {
                    _ = try LyricsFileWriter.write(text, for: row.url, replace: row.replaceLyrics)
                }
                var fresh = FolderAnalyzer.read(row.url)
                fresh.duplicateGroup = row.file.duplicateGroup
                if fresh.duplicateGroup != nil { fresh.issues.insert(.duplicate) }
                rows[i] = MetadataRow(file: fresh, proposal: row.proposal, status: .saved)
                saved += 1
            } catch {
                rows[i].status = .failed(Self.describe(error))
                failed += 1
            }
        }
        message = "\(saved) músicas salvas" + (failed > 0 ? " · \(failed) com erro" : "") + " · backup de cada arquivo guardado"
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
