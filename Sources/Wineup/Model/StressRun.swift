import AppKit
import SwiftUI
import WineupCore
import WineupLibrary

/// Roteiro de carga (WINEUP_STRESS=1): depois da abertura, faz as ações pesadas pelas APIs reais
/// do modelo, mede cada passo e as travadas da thread principal (com WINEUP_HANG_LOG) e encerra o app.
/// Sem som: o volume vai a zero e o player não abre os arquivos (ver `Measure.stress`).
@MainActor
final class StressRun {
    /// Modelo da janela Metadados aberta (registrado pela própria janela durante o roteiro).
    static weak var metadata: MetadataManagerModel?
    private static var current: StressRun?

    private let state: PlayerState
    private let openWindow: (String) -> Void
    private var results: [(step: String, duration: Double)] = []
    private var browser: LibraryBrowser { state.browser }

    private init(state: PlayerState, openWindow: @escaping (String) -> Void) {
        self.state = state
        self.openWindow = openWindow
    }

    static func startIfRequested(state: PlayerState, openWindow: @escaping (String) -> Void) {
        guard Measure.stress, current == nil else { return }
        let run = StressRun(state: state, openWindow: openWindow)
        current = run
        state.volume = 0
        Task { await run.run() }
    }

    // MARK: Roteiro

    private func run() async {
        await pause(Measure.stressDelay)
        await measure("abertura: Músicas (biblioteca)", settle: 1.0) {
            await self.waitUntil(timeout: 120) { !self.browser.isLoading && !self.state.tracks.isEmpty }
        }
        let libraryCount = state.tracks.count
        if Measure.stressOnly == nil { await libraryListSteps(libraryCount) }
        if let folder = Measure.stressFiles.map({ URL(fileURLWithPath: $0, isDirectory: true) }) {
            if Measure.stressOnly != "metadata" { await realFileSteps(folder) }
            if Measure.stressOnly != "files" { await metadataSteps(folder) }
        }
        finish()
    }

    /// Visões, busca, estilos, filtros e reprodução sobre a biblioteca inteira.
    private func libraryListSteps(_ libraryCount: Int) async {
        for mode in [ViewMode.albums, .artists, .genres, .files, .playlists] {
            await measure("visão \(mode.rawValue)") { self.browser.setView(mode); await self.waitLoaded() }
        }
        await openBigPlaylist()
        await measure("visão songs (\(libraryCount))") {
            self.browser.setView(.songs)
            await self.waitUntil { !self.browser.isLoading && self.state.tracks.count >= libraryCount }
        }
        await typeSearch("faixa 12")
        await measure("busca: limpar") { self.state.query = "" }
        for style in [ListStyle.detailed, .grid, .compact] {
            await measure("estilo \(style.rawValue)", settle: 1.0) { self.state.listStyle = style }
        }
        snapshot("lista")
        await measure("rolar lista (\(libraryCount))") { await self.scrollLargestList(in: "main") }
        await measure("filtro de cor (verde)") { self.state.markFilter = .green }
        await measure("filtro de cor (todas)") { self.state.markFilter = nil }
        await measure("selecionar faixa") { self.state.selectedID = self.state.tracks.dropFirst(100).first?.id }
        await playbackSteps()
        await measure("visão queue") { self.browser.setView(.queue) }
        await measure("visão songs (volta)") {
            self.browser.setView(.songs)
            await self.waitUntil { !self.browser.isLoading && self.state.tracks.count >= libraryCount }
        }
    }

    private func openBigPlaylist() async {
        await measure("visão playlists (de novo)") { self.browser.setView(.playlists); await self.waitLoaded() }
        guard let big = browser.groups.filter({ $0.playlistID != nil }).max(by: { $0.count < $1.count }) else { return }
        await measure("abrir playlist (\(big.count))") {
            self.browser.open(big)
            await self.waitUntil { self.state.listTitle == big.title && self.state.tracks.count == big.count }
        }
    }

    /// Digita como uma pessoa: uma letra a cada ~60 ms.
    private func typeSearch(_ text: String) async {
        await measure("busca: digitar \u{201C}\(text)\u{201D}", settle: 0.8) {
            for end in text.indices {
                self.state.query = String(text[...end])
                await self.pause(0.06)
            }
        }
    }

    private func playbackSteps() async {
        let list = state.tracks
        guard let first = list.first else { return }
        await measure("tocar (fila de \(list.count))") { self.state.play(first, from: list) }
        await measure("aleatório: ligar") { self.state.shuffleOn = true }
        await measure("aleatório: desligar") { self.state.shuffleOn = false }
        await measure("próxima ×20") {
            for _ in 0..<20 {
                self.state.step(by: 1)
                await self.pause(0.05)
            }
        }
    }

    private func realFileSteps(_ folder: URL) async {
        let files = await Task.detached { TrackLoader.audioURLs(in: [folder]) }.value
        await measure("abrir \(files.count) arquivos", settle: 1.0) {
            let started = ProcessInfo.processInfo.systemUptime
            self.state.load(urls: files)
            await self.waitUntil(timeout: 180) { self.state.externalList && !self.state.tracks.isEmpty }
            let first = (ProcessInfo.processInfo.systemUptime - started) * 1000
            HangWatchdog.shared?.write(String(format: "primeiras faixas na lista\t%.0f ms\t%d", first, self.state.tracks.count))
            await self.waitUntil(timeout: 180) { self.state.externalList && self.state.tracks.count == files.count }
        }
        await measure("grade com capas (\(files.count))", settle: 2.0) { self.state.listStyle = .grid }
        await measure("rolar grade com capas", settle: 1.0) { await self.scrollLargestList(in: "main") }
        snapshot("grade")
        await measure("lista compacta (\(files.count))") { self.state.listStyle = .compact }
        await measure("arrastar pasta (\(files.count)) para a biblioteca", settle: 1.0) {
            self.state.load(urls: [folder])
            await self.pause(0.3)
            await self.waitUntil(timeout: 300) { !self.state.library.isScanning && !self.browser.isLoading }
        }
    }

    private func metadataSteps(_ folder: URL) async {
        await measure("Metadados: abrir janela") {
            self.openWindow("metadata")
            await self.waitUntil { Self.metadata != nil && Self.metadata?.isLoading == false }
            self.moveWindowsLeft()
        }
        guard let model = Self.metadata else { return }
        await measure("Metadados: analisar pasta", settle: 1.0) {
            model.open(folder)
            await self.waitUntil(timeout: 300) { !model.isLoading && !model.rows.isEmpty }
        }
        snapshot("metadados")
        let orders: [(String, [KeyPathComparator<MetadataRow>])] = [
            ("título", [KeyPathComparator(\.sortTitle)]),
            ("artista ↓", [KeyPathComparator(\.sortArtist, order: .reverse)]),
            ("duração", [KeyPathComparator(\.sortDuration)]),
            ("arquivo", [KeyPathComparator(\.sortFile)]),
        ]
        for (name, order) in orders {
            await measure("Metadados: ordenar por \(name)") { model.sortOrder = order }
        }
        await measure("Metadados: rolar lista") { await self.scrollLargestList(in: "metadata") }
        await measure("Metadados: selecionar tudo (\(model.rows.count))", settle: 1.0) {
            model.selection = Set(model.visibleRows.map(\.id))
        }
        logTableSelection()
        snapshot("metadados-selecao")
        await measure("Metadados: limpar seleção") { model.selection = [] }
        await measure("Metadados: filtro com problemas") { model.filter = .problems }
        await measure("Metadados: filtro todas") { model.filter = .all }
        await measure("Metadados: digitar filtro", settle: 0.8) {
            for end in "faixa 12".indices {
                model.query = String("faixa 12"[...end])
                await self.pause(0.06)
            }
        }
        await measure("Metadados: limpar filtro") { model.query = "" }
    }

    // MARK: Medição

    /// Roda o passo, espera ele terminar e mais `settle` s (o desenho que vem depois conta no passo).
    private func measure(_ name: String, settle: Double = 0.5, _ action: () async -> Void) async {
        HangWatchdog.shared?.setStep(name)
        let signpost = Measure.signposter.beginInterval("stress", id: Measure.signposter.makeSignpostID(), "\(name, privacy: .public)")
        let started = ProcessInfo.processInfo.systemUptime
        await action()
        // Uma volta do loop principal: o desenho do resultado entra na duração.
        await Task.yield()
        let duration = (ProcessInfo.processInfo.systemUptime - started) * 1000
        Measure.signposter.endInterval("stress", signpost)
        results.append((name, duration))
        HangWatchdog.shared?.write(String(format: "fim\t%@\t%.0f ms", name, duration))
        await pause(settle)
    }

    private func waitLoaded() async {
        await waitUntil { !self.browser.isLoading }
    }

    @discardableResult
    private func waitUntil(timeout: Double = 60, _ condition: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition() {
            if ProcessInfo.processInfo.systemUptime > deadline {
                HangWatchdog.shared?.write("tempo esgotado")
                return false
            }
            await pause(0.02)
        }
        return true
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Janelas novas (Metadados) também vão para a tela da esquerda, sem ativar o app.
    /// Rola a maior lista da janela como um gesto rápido: meia tela a cada quadro, 90 quadros.
    private func scrollLargestList(in windowID: String) async {
        guard let window = NSApp.windows.first(where: { $0.isVisible && ($0.identifier?.rawValue ?? "").hasPrefix(windowID) }),
              let root = window.contentView,
              let scroll = Self.scrollViews(in: root).max(by: {
                  ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0)
              }) else {
            HangWatchdog.shared?.write("sem lista para rolar em \(windowID)")
            return
        }
        let clip = scroll.contentView
        for _ in 0..<90 {
            let maxY = max(0, (scroll.documentView?.frame.height ?? 0) - clip.bounds.height)
            let y = min(maxY, clip.bounds.origin.y + clip.bounds.height / 2)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scroll.reflectScrolledClipView(clip)
            await pause(1.0 / 60)
        }
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews(in:))
    }

    /// Confere que a tabela de Metadados mostra a seleção do modelo.
    private func logTableSelection() {
        let window = NSApp.windows.first { ($0.identifier?.rawValue ?? "").hasPrefix("metadata") }
        let tables = window?.contentView.map { Self.scrollViews(in: $0).compactMap { $0.documentView as? NSTableView } } ?? []
        let counts = tables.map { "\($0.selectedRowIndexes.count)/\($0.numberOfRows)" }.joined(separator: " ")
        HangWatchdog.shared?.write("seleção na tabela\t\(counts)\tmodelo \(Self.metadata?.selection.count ?? -1)")
    }

    /// WINEUP_STRESS_SHOTS=<pasta>: guarda a imagem das janelas (conferir o visual sem capturar a tela).
    private func snapshot(_ name: String) {
        guard let folder = Measure.stressShots else { return }
        HangWatchdog.shared?.setStep("captura de tela")
        for (n, window) in NSApp.windows.enumerated() where window.isVisible && window.frame.width > 400 {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(n).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    private func moveWindowsLeft() {
        guard let screen = NSScreen.screens.min(by: { $0.frame.minX < $1.frame.minX }) else { return }
        for window in NSApp.windows where window.isVisible && window.frame.width > 400 {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX,
                                          y: max(screen.visibleFrame.minY, screen.visibleFrame.maxY - window.frame.height)))
        }
    }

    private func finish() {
        let events = HangWatchdog.shared?.allEvents() ?? []
        let stats = HangStats.byStep(events, steps: results.map(\.step))
        var lines = ["== resumo ==", StressReport.header]
        lines += results.map { StressReport.line(step: $0.step, duration: $0.duration, stats: stats[$0.step] ?? HangStats([])) }
        let all = HangStats(events.map(\.milliseconds))
        lines.append(String(format: "total: %d travadas, pior %.0f ms, %.0f ms travado", all.count, all.worst, all.total))
        lines.append("== fim ==")
        HangWatchdog.shared?.write(lines.joined(separator: "\n"))
        PerfLog.record("stress", since: ProcessInfo.processInfo.systemUptime, detail: "fim")
        NSApp.terminate(nil)
    }
}
