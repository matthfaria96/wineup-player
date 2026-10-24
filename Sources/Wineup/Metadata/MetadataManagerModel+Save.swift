import Foundation
import WineupLibrary

/// Resultado da gravação de uma linha (feita fora da thread principal).
struct SaveOutcome: Sendable {
    let id: MetadataRow.ID
    /// A linha como foi gravada: se o usuário mexeu depois, o que mudou é mantido.
    let snapshot: MetadataRow
    /// Entrada do histórico (só quando algo foi escrito, mesmo que depois tenha dado erro).
    let item: SaveBatch.Item?
    /// O arquivo relido depois de gravar; nil quando deu erro.
    let fresh: FixerFile?
    let error: String?
}

extension MetadataManagerModel {
    /// Linhas gravadas por vez fora da thread principal; o progresso avança a cada bloco.
    static let saveChunk = 8

    // MARK: Gravação

    func save(onlySelection: Bool) {
        guard let writer else { message = String(localized: "Biblioteca indisponível: não é possível gravar."); return }
        guard !isBusy else { message = String(localized: "Espere a tarefa em andamento terminar (ou pare a busca) para salvar."); return }
        let targets = (onlySelection ? selectedRows : rows).filter(\.isDirty)
        guard !targets.isEmpty else { message = String(localized: "Nenhuma alteração para salvar."); return }
        let mode = coverSaveMode
        let history = history
        let folderPath = folder?.path ?? ""
        let chunks = stride(from: 0, to: targets.count, by: Self.saveChunk).map {
            Array(targets[$0..<min($0 + Self.saveChunk, targets.count)])
        }
        let token = beginWork(total: targets.count)
        // Referência forte de propósito: mesmo com a janela fechada, o que foi gravado entra no histórico.
        work = Task { [self] in
            var saved = 0, failed = 0, done = 0
            var items: [SaveBatch.Item] = []
            for chunk in chunks {
                // Parar interrompe entre blocos; o que já foi gravado continua no histórico.
                if Task.isCancelled { break }
                let outcomes = await Task.detached(priority: .userInitiated) {
                    chunk.map { Self.saveOne($0, writer: writer, history: history, mode: mode) }
                }.value
                applySaved(outcomes)
                saved += outcomes.filter { $0.fresh != nil }.count
                failed += outcomes.filter { $0.error != nil }.count
                items += outcomes.compactMap(\.item)
                done += chunk.count
                if workToken == token { progress = (done, targets.count) }
            }
            if !items.isEmpty {
                let batch = SaveBatch(folder: folderPath, items: items)
                let list = await Task.detached(priority: .userInitiated) { () -> [SaveBatch] in
                    try? history.add(batch)
                    return history.batches()
                }.value
                batches = list
            }
            message = String(localized: "\(saved) músicas salvas")
                + (failed > 0 ? String(localized: " · \(failed) com erro") : "")
                + String(localized: " · dá para desfazer em Histórico (⌘Z)")
            endWork(token)
        }
    }

    /// Grava uma linha: tags (com backup e diário), capa na pasta, letra; relê o arquivo no fim.
    nonisolated static func saveOne(_ row: MetadataRow, writer: TagWriter, history: SaveHistoryStore,
                                    mode: CoverSaveMode) -> SaveOutcome {
        var item = SaveBatch.Item(path: row.url.path)
        func recorded() -> SaveBatch.Item? {
            item.journalID != nil || item.wroteLyrics || !item.createdFiles.isEmpty ? item : nil
        }
        do {
            var changes = row.tagChanges
            if mode == .folder { changes.cover = nil }
            if !changes.isEmpty {
                guard row.file.isWritable else { throw TagWriterError.unsupportedFormat }
                item.journalID = try writer.apply(changes, url: row.url).id
            }
            // Capa também (ou só) como imagem na pasta, sem trocar uma que já exista.
            if let cover = row.cover, mode != .embed, let created = writeFolderCover(cover, beside: row.url) {
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
            return SaveOutcome(id: row.id, snapshot: row, item: recorded(), fresh: fresh, error: nil)
        } catch {
            return SaveOutcome(id: row.id, snapshot: row, item: recorded(), fresh: nil, error: describe(error))
        }
    }

    /// Põe o resultado de um bloco nas linhas, de uma vez.
    private func applySaved(_ outcomes: [SaveOutcome]) {
        let byID = Dictionary(outcomes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        updateRows(byID.keys) { row in
            guard let outcome = byID[row.id] else { return }
            guard let fresh = outcome.fresh else {
                row.status = .failed(outcome.error ?? String(localized: "Erro ao gravar"))
                return
            }
            row = Self.savedRow(current: row, snapshot: outcome.snapshot, fresh: fresh)
        }
    }

    /// Linha depois de gravar; edições feitas enquanto a gravação rodava continuam pendentes.
    static func savedRow(current: MetadataRow, snapshot: MetadataRow, fresh: FixerFile) -> MetadataRow {
        var next = MetadataRow(file: fresh, proposal: current.proposal, status: .saved, ignored: current.ignored)
        guard current.edits != snapshot.edits || current.cover != snapshot.cover || current.lyrics != snapshot.lyrics
        else { return next }
        for (field, value) in current.edits where snapshot.edits[field] != value { next.set(field, value) }
        if current.cover != snapshot.cover { next.cover = current.cover }
        if current.lyrics != snapshot.lyrics { next.setLyrics(current.lyrics) }
        next.refreshStatus()
        return next
    }

    // MARK: Problemas ignorados

    /// Ignora problemas nas linhas (todos os abertos, ou só `issue`); fica salvo para as próximas análises.
    func ignore(_ issue: FixerIssue?, ids: Set<MetadataRow.ID>) {
        var changes: [String: Set<FixerIssue>] = [:]
        updateRows(ids) { row in
            row.ignored.formUnion(issue.map { [$0] } ?? Set(row.openIssues))
            changes[row.url.path] = row.ignored
        }
        persistIgnored(changes)
    }

    func unignore(ids: Set<MetadataRow.ID>) {
        var changes: [String: Set<FixerIssue>] = [:]
        updateRows(ids) { row in
            row.ignored = []
            changes[row.url.path] = []
        }
        persistIgnored(changes)
    }

    /// Uma gravação do JSON por ação, fora da thread principal e na ordem em que as ações vieram.
    private func persistIgnored(_ changes: [String: Set<FixerIssue>]) {
        guard !changes.isEmpty else { return }
        let previous = ignoreWrite
        ignoreWrite = Task.detached(priority: .utility) {
            await previous?.value
            try? IgnoredIssuesStore.shared.set(changes)
        }
    }

    // MARK: Duplicadas

    /// Manda os arquivos para a Lixeira (com o .lrc ao lado, se houver) e tira da lista.
    func trash(paths: Set<String>) async {
        let failed = await Task.detached(priority: .userInitiated) { Self.moveToTrash(paths) }.value
        let removed = paths.subtracting(failed)
        let remaining = rows.filter { !removed.contains($0.url.path) }.map(\.file)
        let regrouped = await Task.detached(priority: .userInitiated) { FolderAnalyzer.markDuplicates(remaining) }.value
        // As linhas podem ter mudado durante a espera: do novo cálculo só vem o grupo de duplicadas.
        let groups = Dictionary(regrouped.map { ($0.id, $0.duplicateGroup) }, uniquingKeysWith: { a, _ in a })
        replaceRows(rows.filter { !removed.contains($0.url.path) }.map { old in
            guard let group = groups[old.id] else { return old }
            var file = old.file
            file.duplicateGroup = group
            if group != nil { file.issues.insert(.duplicate) } else { file.issues.remove(.duplicate) }
            var row = old
            row.file = file
            return row
        })
        selection.subtract(removed)
        let names = failed.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted()
        message = String(localized: "\(removed.count) arquivo(s) na Lixeira")
            + (names.isEmpty ? "" : String(localized: " · não deu: \(names.joined(separator: ", "))"))
    }

    /// Devolve os caminhos que não foram para a Lixeira.
    nonisolated static func moveToTrash(_ paths: Set<String>) -> Set<String> {
        var failed: Set<String> = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                let lrc = url.deletingPathExtension().appendingPathExtension("lrc")
                if FileManager.default.fileExists(atPath: lrc.path) { try? FileManager.default.trashItem(at: lrc, resultingItemURL: nil) }
            } catch {
                failed.insert(path)
            }
        }
        return failed
    }

    // MARK: Capa na pasta

    /// Grava cover.jpg/png na pasta da música se ainda não há capa solta lá. Devolve o arquivo criado.
    nonisolated static func writeFolderCover(_ cover: CoverImage, beside audio: URL) -> URL? {
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

    func refreshHistory() { batches = history.batches() }

    var lastUndoable: SaveBatch? { batches.first { !$0.undone } }

    /// Desfaz um lote inteiro e relê os arquivos afetados que estão na lista (tudo fora da thread principal).
    func undo(_ batch: SaveBatch) {
        guard let writer else { return }
        guard !isBusy else { message = String(localized: "Espere a tarefa em andamento terminar para desfazer."); return }
        let paths = Set(batch.items.map(\.path))
        let urls = rows.filter { paths.contains($0.url.path) }.map(\.url)
        let history = history
        let token = beginWork(total: batch.items.count)
        work = Task { [self] in
            let (result, fresh, list) = await Task.detached(priority: .userInitiated) {
                let result = BatchUndo.undo(batch, writer: writer)
                if result.failed.isEmpty || result.restored > 0 { try? history.markUndone(batch.id) }
                return (result, urls.map(FolderAnalyzer.read), history.batches())
            }.value
            batches = list
            let byPath = Dictionary(fresh.map { ($0.url.path, $0) }, uniquingKeysWith: { a, _ in a })
            updateRows(rows.filter { byPath[$0.url.path] != nil }.map(\.id)) { row in
                guard var file = byPath[row.url.path] else { return }
                file.duplicateGroup = row.file.duplicateGroup
                if file.duplicateGroup != nil { file.issues.insert(.duplicate) }
                row = MetadataRow(file: file, ignored: row.ignored)
            }
            message = String(localized: "\(result.restored) músicas voltaram ao que eram")
                + (result.failed.isEmpty ? ""
                   : String(localized: " · não deu para desfazer: \(result.failed.joined(separator: ", ")) (alterado depois por outro programa?)"))
            endWork(token)
        }
    }
}
