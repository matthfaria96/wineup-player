import AppKit
import Foundation
import WineupAudio
import WineupCore
import WineupLibrary

/// Estado do player. Faixas com `url` tocam de verdade; as de exemplo (sem url) só animam a interface.
final class PlayerState: ObservableObject {
    @Published var tracks: [Track] = [] {
        didSet {
            refreshVisible()
            refreshCurrentPosition()
            if !search.query.isEmpty { refreshSearchResults() }
        }
    }
    /// Lista exibida (com o filtro de cor aplicado), guardada pronta.
    private(set) var visibleTracks: [Track] = []
    /// Linhas da lista exibida (identidade estável), montadas uma vez por mudança e não a cada desenho.
    private(set) var visibleRows: [ListRow] = []
    /// Letra sincronizada da faixa atual (.lrc ao lado do arquivo ou embutida com marcas de tempo).
    var timedLyrics: TimedLyrics? { didSet { updateLyricIndex() } }
    @Published var currentID: TrackID? { didSet { if currentID != oldValue { refreshCurrentPosition() } } }
    /// Seleção à parte: mudar a faixa selecionada redesenha só as linhas, não o painel.
    let selection = SelectionModel()
    var selectedID: TrackID? {
        get { selection.selectedID }
        set {
            guard newValue != selection.selectedID else { return }
            let started = ProcessInfo.processInfo.systemUptime
            selection.selectedID = newValue
            DispatchQueue.main.async { PerfLog.record("select", since: started) }
        }
    }
    @Published var isPlaying = false {
        didSet {
            guard isPlaying != oldValue else { return }
            updateTicker()
            let playing = isPlaying
            MainActor.assumeIsolated { WindowVisibility.shared.setPlaying(playing) }
        }
    }
    /// Relógio da posição: roda enquanto toca, mesmo com a janela fechada (modo barra de menus).
    private var ticker: Timer?
    private static let tickInterval = 0.25
    /// Relógio separado: só o Player e as Letras redesenham a cada atualização de posição.
    let clock = PlaybackClock()
    var progress: Double {
        get { clock.progress }
        set {
            guard clock.progress != newValue else { return }
            clock.progress = newValue
            updateLyricIndex()
        }
    }
    /// Lado do som: -1 = música inteira na esquerda, 0 = normal, 1 = inteira na direita.
    @Published var side = UserDefaults.standard.integer(forKey: "side") {
        didSet { audio.setSide(side); UserDefaults.standard.set(side, forKey: "side") }
    }
    /// Velocidade de 0,5× (2× mais lenta) a 2×, em passos de 0,25.
    @Published var playbackRate = PlayerState.saved("playbackRate", 1.0) {
        didSet { audio.setRate(playbackRate); UserDefaults.standard.set(playbackRate, forKey: "playbackRate") }
    }
    /// Faixa e passos da velocidade (menu de velocidade e atalhos).
    static let rateRange: ClosedRange<Double> = 0.5...3.0
    static let rateStep = 0.05
    static let ratePresets: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    /// Soma passos de 0,05× (arredondado, dentro de 0,5×...3×).
    func changeRate(by steps: Int) {
        setRate(playbackRate + Double(steps) * Self.rateStep)
    }

    func setRate(_ rate: Double) {
        let clamped = min(max(rate, Self.rateRange.lowerBound), Self.rateRange.upperBound)
        playbackRate = (clamped / Self.rateStep).rounded() * Self.rateStep
    }
    /// Fila de reprodução: a lista de onde a música foi tocada (navegar não interrompe a sequência).
    @Published var queue = PlaybackQueue<Track>() {
        // Visão "Fila" aberta: acompanha a fila ao vivo.
        didSet { if browser.view == .queue, queue.items != oldValue.items { tracks = queue.items } }
    }
    @Published var repeatMode: RepeatMode = RepeatMode(rawValue: UserDefaults.standard.string(forKey: "repeatMode") ?? "") ?? .off {
        didSet {
            UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
            queue = queue.withRepeat(repeatMode)
            reenqueue()
        }
    }
    @Published var shuffleOn = UserDefaults.standard.bool(forKey: "shuffle") {
        didSet {
            UserDefaults.standard.set(shuffleOn, forKey: "shuffle")
            queue = shuffleOn ? queue.shuffled(seed: UInt64.random(in: 1...UInt64.max)) : queue.unshuffled()
            reenqueue()
        }
    }
    /// Posição (0...1) para retomar a última faixa da sessão anterior.
    var resumeFraction: Double?
    @Published var replayGainMode: ReplayGainMode = .track { didSet { audio.replayGainMode = replayGainMode } }
    @Published var preventClipping = true { didSet { audio.preventClipping = preventClipping } }
    /// Correção de Som: todas as músicas no mesmo volume percebido (mede cada uma, sem mexer no arquivo).
    @Published var soundCorrection = UserDefaults.standard.bool(forKey: "soundCorrection") {
        didSet {
            UserDefaults.standard.set(soundCorrection, forKey: "soundCorrection")
            audio.soundCorrection = soundCorrection
        }
    }
    /// Nível alvo em LUFS (-18 baixo, -14 padrão, -11 alto).
    @Published var correctionTarget = PlayerState.saved("soundCorrectionTarget", SoundCorrection.defaultTarget) {
        didSet {
            UserDefaults.standard.set(correctionTarget, forKey: "soundCorrectionTarget")
            audio.correctionTarget = correctionTarget
        }
    }
    /// Mensagens e progresso ficam num objeto à parte: mudar o aviso não redesenha a janela inteira.
    let status = StatusModel()
    var loudnessProgress: (done: Int, total: Int)? {
        get { status.loudnessProgress }
        set { status.loudnessProgress = newValue }
    }
    private var loudnessTask: Task<Void, Never>?
    @Published var outputSampleRate: Double?
    @Published var eqBypass = false { didSet { syncEqualizer() } }
    @Published var preset = "Flat"
    @Published var presets: [EqPreset] = EqPreset.builtIns
    /// Busca à parte: cada tecla redesenha só a caixa de busca e a lista.
    let search = SearchModel()
    var query: String {
        get { search.query }
        set { search.query = newValue }
    }
    var libraryResults: [Track] = [] { didSet { refreshSearchResults() } }
    @Published var markFilter: MarkColor? { didSet { refreshVisible() } }
    @Published var lyricsScale = 1.0
    @Published var cover: NSImage?
    @Published var lyricLines: [String] = [] { didSet { updateLyricIndex() } }
    /// Linha ativa da letra, publicada à parte e só quando muda.
    let lyricsPosition = LyricsPosition()
    /// De onde veio a letra exibida: arquivo local ou catálogo online (ainda não salva).
    @Published var lyricsOrigin: LyricsOrigin = .none
    /// Buscar online quando a faixa não tem letra local (envia título, artista, álbum e duração).
    @Published var lyricsOnline = UserDefaults.standard.object(forKey: "lyrics.online") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(lyricsOnline, forKey: "lyrics.online")
            if let track = currentTrack { refreshDetails(for: track) }
        }
    }
    var statusMessage: String? {
        get { status.message }
        set { if status.message != newValue { status.message = newValue } }
    }
    /// Nome do que está na lista agora (álbum, banda, pasta, estilo ou playlist).
    @Published var listTitle = String(localized: "Playlist")
    @Published var listStyle: ListStyle = ListStyle(rawValue: UserDefaults.standard.string(forKey: DisplayKeys.listStyle) ?? "") ?? .compact {
        didSet { UserDefaults.standard.set(listStyle.rawValue, forKey: DisplayKeys.listStyle) }
    }

    /// Volume e EQ à parte: arrastar um slider redesenha só o controle, não a lista.
    let mixer = MixerModel(volume: Measure.mute ? 0 : PlayerState.saved("volume", 0.8))
    var volume: Double {
        get { mixer.volume }
        set { mixer.volume = newValue }
    }

    static func saved(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }
    var preamp: Double {
        get { mixer.preamp }
        set { mixer.preamp = newValue }
    }
    var bands: [Double] {
        get { mixer.bands }
        set { mixer.bands = newValue }
    }

    private let audio = SFBAudioEngineAdapter()
    let library = LibraryController()
    let browser: LibraryBrowser
    /// Última faixa tocada, para o player continuar mostrando-a quando a lista muda de grupo.
    var lastPlayed: Track?
    private var searchTask: Task<Void, Never>?
    /// Leitura dos arquivos abertos (⌘O, Finder, arrastar), em lotes.
    private var filesTask: Task<Void, Never>?
    /// Filtro da lista aberta (busca sem resultado na biblioteca), feito fora da thread principal.
    private var listFilterTask: Task<Void, Never>?
    private var usingSampleTracks = true
    private var restoredOnce = false
    /// Arquivos abertos pelo Finder/⌘O antes da biblioteca carregar: a lista fica com eles.
    private var openedFilesFirst = false
    /// A lista atual veio de arquivos abertos ou de um M3U (não do visualizador).
    var externalList = false
    /// Falhas seguidas ao tocar (para não pular a fila inteira em laço).
    var consecutiveFailures = 0
    private var eqSaveTask: Task<Void, Never>?

    init() {
        browser = LibraryBrowser(database: library.database)
        search.onChange = { [weak self] _ in
            self?.scheduleLibrarySearch()
            self?.refreshSearchResults()
        }
        mixer.onVolume = { [weak self] volume in
            self?.audio.setVolume(volume)
            if !Measure.mute { UserDefaults.standard.set(volume, forKey: "volume") }
        }
        mixer.onEqualizer = { [weak self] in self?.syncEqualizer() }
        audio.onTrackChanged = { [weak self] url, fromQueue in self?.nowPlayingChanged(url, fromQueue: fromQueue) }
        audio.onEndOfAudio = { [weak self] in self?.endOfAudio() }
        audio.onError = { [weak self] message in self?.skipAfterFailure(String(localized: "Erro ao tocar: \(message)")) }
        audio.onDecodingFailed = { [weak self] url, message, ended in
            self?.decodingFailed(url, message: String(localized: "Erro ao tocar: \(message)"), ended: ended)
        }
        audio.onConfigurationChange = { [weak self] rate in self?.outputSampleRate = rate }
        audio.setVolume(volume)
        audio.setRate(playbackRate)
        audio.setBalance(0)
        if side != 0 { audio.setSide(side) }
        audio.replayGainMode = replayGainMode
        audio.preventClipping = preventClipping
        audio.correctionTarget = correctionTarget
        audio.soundCorrection = soundCorrection
        restoreEqualizer()
        syncEqualizer()
        browser.onShowTracks = { [weak self] title, items in self?.showTracks(title: title, items: items) }
        browser.queueProvider = { [weak self] in self?.queue.items ?? [] }
        browser.onRescan = { [weak self] in Task { @MainActor in self?.library.rescan() } }
        NowPlaying.attach(self)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.saveSession() }
    }

    var meter: LevelTap { audio.meter }
    /// Modelo do medidor, fora do PlayerPanel para que só o medidor redesenhe a 30 Hz.
    private(set) lazy var meterModel: MeterModel = MainActor.assumeIsolated { MeterModel() }


    /// Lida várias vezes por desenho (player, capa, letras): usa a posição guardada, sem varrer a lista
    /// (com 50 mil faixas e nada tocando, cada leitura percorria a lista inteira).
    var currentTrack: Track? {
        if let current = queue.current { return current }
        guard let id = currentID else { return nil }
        if let position = currentPosition, tracks.indices.contains(position - 1), tracks[position - 1].id == id {
            return tracks[position - 1]
        }
        return lastPlayed.flatMap { $0.id == id ? $0 : nil }
    }

    /// Posição 1-based da faixa atual na lista (guardada; recalculada quando a lista ou a faixa muda).
    private(set) var currentPosition: Int?

    private func refreshCurrentPosition() {
        currentPosition = currentID.flatMap { id in tracks.firstIndex { $0.id == id } }.map { $0 + 1 }
    }

    private func refreshVisible() {
        visibleTracks = markFilter.map { color in tracks.filter { $0.mark == color } } ?? tracks
        visibleRows = ListRow.rows(visibleTracks)
    }

    /// Resultados guardados (antes eram filtrados a cada leitura, duas vezes por desenho).
    var searchResults: [Track] { search.results }

    private func refreshSearchResults() {
        listFilterTask?.cancel()
        let needle = query.trimmingCharacters(in: .whitespaces)
        if needle.isEmpty { publishSearch([]); return }
        if library.isAvailable, !libraryResults.isEmpty { publishSearch(libraryResults); return }
        // Sem resultado na biblioteca (ou fora dela): filtra a lista aberta fora da thread principal,
        // depois de uma pausa entre teclas (com 50 mil faixas, filtrar a cada tecla travava ~40 ms).
        let list = tracks
        listFilterTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) { TrackList.matching(needle, in: list) }.value
            guard !Task.isCancelled, let self, self.query.trimmingCharacters(in: .whitespaces) == needle else { return }
            self.publishSearch(found)
        }
    }

    private func publishSearch(_ found: [Track]) {
        if found != search.results { search.results = found }
    }

    var remainingSeconds: Int {
        guard let track = currentTrack else { return 0 }
        if track.url != nil, audio.totalTime > 0, track.isSegment {
            let (_, end) = bounds(of: track)
            return Int(max(end - audio.currentTime, 0) / playbackRate)
        }
        if track.url != nil, audio.totalTime > 0 {
            return Int(RateMapping.remainingWallSeconds(
                total: audio.totalTime, current: audio.currentTime, rate: playbackRate))
        }
        return Int(Double(track.duration) * (1 - progress) / playbackRate)
    }

    var activeLyricIndex: Int { lyricsPosition.index }

    /// Recalcula a linha ativa (no tique, ao pular e ao trocar a letra); publica só se mudou.
    func updateLyricIndex() {
        let index: Int
        if lyricLines.isEmpty { index = 0 }
        else if let timed = timedLyrics { index = timed.index(at: elapsedInTrack) ?? 0 }
        else { index = min(Int(progress * Double(lyricLines.count)), lyricLines.count - 1) }
        if index != lyricsPosition.index { lyricsPosition.index = index }
    }

    private func updateTicker() {
        // O relógio vive na thread principal (avisos do áudio podem chegar de outra).
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.updateTicker() }
            return
        }
        if isPlaying {
            guard ticker == nil else { return }
            let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                self?.tick(Self.tickInterval)
            }
            // .common: continua durante arrastos e menus abertos.
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
            MainActor.assumeIsolated { meterModel.wake() }
        } else {
            ticker?.invalidate()
            ticker = nil
        }
    }

    /// Segundos tocados da faixa atual (para CUE, contados a partir do início do trecho).
    var elapsedInTrack: Double {
        guard let track = currentTrack else { return 0 }
        if track.url != nil, audio.totalTime > 0 { return max(0, audio.currentTime - (track.start ?? 0)) }
        return progress * Double(track.duration)
    }

    /// Início e fim (s) do trecho tocado: arquivo inteiro ou faixa de CUE.
    private func bounds(of track: Track) -> (start: Double, end: Double) {
        let start = track.start ?? 0
        return (start, track.end ?? max(audio.totalTime, start + Double(track.duration)))
    }

    // MARK: Biblioteca

    func startLibrary() async {
        await library.start(
            onChange: { [weak self] in self?.applyLibraryChange() },
            onStatus: { [weak self] message in self?.statusMessage = message })
    }

    /// A biblioteca carregou/terminou uma varredura.
    private func applyLibraryChange() {
        if usingSampleTracks {
            // Primeira carga: abre a pasta padrão (pergunta qual é, na primeira vez).
            usingSampleTracks = false
            if NavPlaces.defaultFolder == nil { askDefaultFolder() }
            browser.load()
        } else {
            browser.libraryChanged()
        }
    }

    /// Mostra na lista o que o visualizador entregou.
    func showTracks(title: String, items: [Track]) {
        // Lista aberta à mão (arquivos, M3U): só a navegação do usuário a substitui.
        if externalList && browser.isBackgroundRefresh { return }
        externalList = false
        if openedFilesFirst && !restoredOnce {
            restoredOnce = true   // a primeira carga da biblioteca não substitui os arquivos abertos
            return
        }
        let started = ProcessInfo.processInfo.systemUptime
        // Mede até a próxima volta do loop principal (layout + desenho da lista).
        DispatchQueue.main.async { PerfLog.record("render", since: started, detail: "\(items.count) faixas") }
        listTitle = title
        tracks = items
        // Recarga automática: a seleção fica se a faixa continua na lista.
        if !browser.isBackgroundRefresh || !items.contains(where: { $0.id == selectedID }) { selectedID = nil }
        if !restoredOnce {
            restoredOnce = true
            if ProcessInfo.processInfo.environment["WINEUP_AUTOPLAY"] != nil, let first = items.first {
                play(first, from: items)
            } else {
                restoreSession(in: items)
            }
        }
    }

    func track(from item: LibraryTrack) -> Track { browser.track(from: item) }

    private func scheduleLibrarySearch() {
        searchTask?.cancel()
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard library.isAvailable else { return }
        guard !needle.isEmpty else { libraryResults = []; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            let found = await self.library.search(needle)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.libraryResults = found.map(self.track(from:)) }
        }
    }

    func load(urls: [URL]) {
        // Skin arrastado para a janela: tela "Sobre o skin".
        let skins = urls.filter { $0.pathExtension.lowercased() == "wineupskin" }
        skins.forEach { url in MainActor.assumeIsolated { SkinInstaller.present(url) } }
        let urls = urls.filter { $0.pathExtension.lowercased() != "wineupskin" }
        guard !urls.isEmpty else { return }
        // Playlists M3U/M3U8 abrem como lista.
        let playlists = urls.filter { ["m3u", "m3u8"].contains($0.pathExtension.lowercased()) }
        if let first = playlists.first {
            openM3U(first)
            let rest = urls.filter { !playlists.contains($0) }
            if rest.isEmpty { return }
            return load(urls: rest)
        }
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if library.isAvailable, !folders.isEmpty {
            Task { await library.addFolders(folders) }
            let files = urls.filter { !folders.contains($0) }
            if files.isEmpty { return }
            loadFiles(files)
            return
        }
        loadFiles(urls)
    }

    /// Abre arquivos soltos: as tags são lidas em paralelo fora da thread principal e a lista cresce em lotes
    /// (os primeiros já tocam enquanto o resto é lido; antes, 5 mil arquivos esperavam ~3 s sem nada na tela).
    private func loadFiles(_ urls: [URL]) {
        filesTask?.cancel()
        filesTask = Task { @MainActor [weak self] in
            let found = await Task.detached(priority: .userInitiated) { TrackLoader.audioURLs(in: urls) }.value
            guard let self, !Task.isCancelled else { return }
            guard !found.isEmpty else {
                self.statusMessage = String(localized: "Nenhum áudio suportado encontrado.")
                return
            }
            var shown = 0
            for await batch in TrackLoader.trackBatches(found) {
                guard !Task.isCancelled else { return }
                if shown == 0 {
                    self.showOpenedFiles(batch)
                } else {
                    // O usuário abriu outra lista no meio da leitura: o resto não entra nela.
                    guard self.externalList, self.tracks.count == shown else { return }
                    self.appendOpenedFiles(batch)
                }
                shown += batch.count
                if shown < found.count {
                    self.statusMessage = String(localized: "Abrindo arquivos: \(shown) de \(found.count)…")
                }
            }
            if self.externalList, self.tracks.count == found.count { self.statusMessage = nil }
        }
    }

    /// Primeiro lote: substitui a lista e toca a primeira faixa.
    private func showOpenedFiles(_ loaded: [Track]) {
        stop()
        if !restoredOnce { openedFilesFirst = true }
        externalList = true
        tracks = loaded
        currentID = loaded.first?.id
        selectedID = nil
        statusMessage = nil
        if let first = loaded.first { play(first) }
    }

    /// Lotes seguintes: entram no fim da lista e, se a fila é esta lista, no fim da fila também.
    private func appendOpenedFiles(_ batch: [Track]) {
        let previous = tracks
        let queueIsList = queue.items.count == previous.count && queue.items.first?.id == previous.first?.id
            && queue.items.last?.id == previous.last?.id
        tracks = previous + batch
        guard queueIsList else { return }
        // A próxima pré-carregada muda se a atual era a última ou se a ordem é aleatória.
        let nextChanges = queue.currentIndex == previous.count - 1 || queue.isShuffled
        queue = queue.appending(batch)
        if nextChanges { reenqueue() }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Escolha arquivos de áudio ou pastas de música")
        if panel.runModal() == .OK { load(urls: panel.urls) }
    }

    // MARK: Reprodução

    /// Toca uma faixa e monta a fila com a lista de onde ela veio (padrão: a lista aberta).
    func play(_ track: Track, from list: [Track]? = nil) {
        let source = list ?? (tracks.contains { $0.id == track.id } ? tracks : [track])
        let index = source.firstIndex { $0.id == track.id } ?? 0
        var newQueue = PlaybackQueue(items: source, currentIndex: index).withRepeat(repeatMode)
        if shuffleOn { newQueue = newQueue.shuffled(seed: UInt64.random(in: 1...UInt64.max)) }
        queue = newQueue
        startCurrent()
    }

    func startCurrentPublic() { startCurrent() }

    /// Toca o item atual da fila (sem remontá-la).
    private func startCurrent(resumeAt fraction: Double? = nil) {
        guard let track = queue.current else { return }
        lastPlayed = track
        currentID = track.id
        selectedID = track.id
        progress = 0
        refreshDetails(for: track)
        // Roteiro de carga: nunca abre o arquivo (sem som enquanto a pessoa usa o Mac).
        if let url = track.url, !Measure.stress {
            do {
                // Início do trecho (CUE) ou ponto da sessão anterior: posicionado antes de tocar
                // (um seek logo depois de play() era descartado).
                var start: SFBAudioEngineAdapter.StartPoint?
                if let segmentStart = track.start, segmentStart > 0 {
                    start = .time(segmentStart)
                } else if let fraction, fraction > 0, !track.isSegment {
                    start = .fraction(fraction)
                }
                try audio.play(url, from: start)
                enqueueNext(after: track)
                isPlaying = true
                statusMessage = nil
                saveSession()
                NowPlaying.update(self)
            } catch {
                isPlaying = false
                skipAfterFailure(String(localized: "Não foi possível tocar \u{201C}\(track.title)\u{201D}: \(error.localizedDescription)"))
            }
        } else {
            isPlaying = true
        }
    }

    func togglePlay() {
        guard let track = currentTrack else {
            // Nada carregado: toca a selecionada ou a primeira da lista.
            let pick = selectedID.flatMap { id in visibleTracks.first { $0.id == id } } ?? visibleTracks.first
            if let pick { play(pick, from: visibleTracks) }
            return
        }
        if isPlaying {
            audio.pause()
            isPlaying = false
        } else if audio.currentTime > 0 {
            audio.resume()
            isPlaying = true
        } else if queue.current?.id == track.id {
            let resume = resumeFraction
            resumeFraction = nil
            startCurrent(resumeAt: resume)
        } else {
            play(track)
        }
        NowPlaying.update(self)
    }

    func pause() {
        if currentTrack?.url != nil { audio.pause() }
        isPlaying = false
        NowPlaying.update(self)
    }

    func stop() {
        audio.stop()
        isPlaying = false
        progress = 0
        NowPlaying.update(self)
    }

    func seek(to fraction: Double) {
        progress = min(max(fraction, 0), 1)
        if let track = currentTrack, track.url != nil {
            if track.isSegment {
                let (start, end) = bounds(of: track)
                audio.seek(toTime: start + progress * (end - start))
            } else {
                audio.seek(toFraction: progress)
            }
        }
        NowPlaying.update(self)
    }

    /// Próxima/anterior pela fila. "Repetir uma" não prende o botão: avança normalmente.
    func step(by offset: Int) {
        let manual = repeatMode == .one ? queue.withRepeat(.all) : queue
        guard let index = offset >= 0 ? manual.nextIndex() : manual.previousIndex() else {
            stop()
            return
        }
        queue = queue.selecting(index: index)
        startCurrent()
    }

    func playRandom() {
        if let track = visibleTracks.randomElement() { play(track, from: visibleTracks) }
    }

    func deleteSelected() {
        guard let selectedID else { return }
        tracks = TrackList.removing(selectedID, from: tracks)
        self.selectedID = nil
    }

    func tick(_ delta: Double) {
        guard isPlaying, let track = currentTrack else { return }
        if track.url != nil {
            let total = audio.totalTime
            guard total > 0 else { return }
            let (start, end) = bounds(of: track)
            let current = audio.currentTime
            progress = min(max((current - start) / max(end - start, 0.001), 0), 1)
            // Faixa de CUE: ao chegar ao fim do trecho, vai para a próxima.
            if track.end != nil, current >= end - 0.05 { step(by: 1) }
        } else if track.duration > 0 {
            let next = progress + delta * playbackRate / Double(track.duration)
            if next >= 1 { step(by: 1) } else { progress = next }
        }
    }

    func apply(preset name: String) {
        preset = name
        guard let found = presets.first(where: { $0.name == name }) else { return }
        preamp = found.preamp
        bands = found.bands
    }

    var isUserPreset: Bool { !EqPreset.isBuiltInName(preset) && presets.contains { $0.name == preset } }

    func savePreset(named name: String) {
        guard let store = library.presetStore else { statusMessage = String(localized: "Biblioteca indisponível para salvar presets."); return }
        guard let valid = EqPreset.validated(name: name, preamp: preamp, bands: bands) else {
            statusMessage = String(localized: "Nome de preset inválido (1 a \(EqPreset.maxNameLength) caracteres).")
            return
        }
        do {
            try store.save(valid)
            reloadPresets(store)
            preset = valid.name
            syncEqualizer()
        } catch { statusMessage = Self.presetMessage(error) }
    }

    func renamePreset(_ old: String, to new: String) {
        guard let store = library.presetStore else { return }
        do {
            try store.rename(from: old, to: new)
            reloadPresets(store)
            if preset == old { preset = new.trimmingCharacters(in: .whitespacesAndNewlines) }
            syncEqualizer()
        } catch { statusMessage = Self.presetMessage(error) }
    }

    func deletePreset(_ name: String) {
        guard let store = library.presetStore else { return }
        do {
            try store.delete(name: name)
            reloadPresets(store)
            if preset == name { preset = "Custom" }
            syncEqualizer()
        } catch { statusMessage = Self.presetMessage(error) }
    }

    private func reloadPresets(_ store: EqPresetStore) {
        presets = (try? store.allPresets()) ?? EqPreset.builtIns
    }

    private static func presetMessage(_ error: Error) -> String {
        switch error as? EqPresetStoreError {
        case .duplicateName: return String(localized: "Já existe um preset com esse nome.")
        case .reservedName: return String(localized: "Esse nome é reservado a um preset embutido.")
        case .notFound: return String(localized: "Preset não encontrado.")
        default: return String(localized: "Não foi possível salvar o preset.")
        }
    }

    private func restoreEqualizer() {
        guard let store = library.presetStore else { return }
        reloadPresets(store)
        guard let saved = store.loadCurrent() else { return }
        eqBypass = saved.bypass
        // A curva de exemplo das primeiras versões (e os presets antigos, mais fortes) voltam ao padrão atual.
        if saved.bands == SampleData.legacyCustomCurve {
            apply(preset: "Flat")
            return
        }
        if let name = saved.presetName, EqPreset.isBuiltInName(name) {
            apply(preset: name)
            preamp = saved.preamp
            return
        }
        preamp = saved.preamp
        bands = saved.bands
        preset = saved.presetName ?? "Custom"
    }

    private func persistEqualizer() {
        guard let store = library.presetStore else { return }
        let state = EqState(preamp: preamp, bands: bands, bypass: eqBypass, presetName: preset)
        eqSaveTask?.cancel()
        eqSaveTask = Task.detached {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            store.saveCurrent(state)
        }
    }

    // MARK: Privado

    private func enqueueNext(after track: Track) {
        guard let index = queue.nextIndex(), let url = queue.items[index].url,
              !track.isSegment, !queue.items[index].isSegment else {
            // Sem próxima válida: não deixa um decoder antigo na fila do player.
            audio.clearQueue()
            return
        }
        try? audio.enqueue(url)
    }

    /// Refaz o pré-enfileiramento quando repetir/aleatório/fila mudam (também pausado).
    func reenqueue() {
        guard let track = queue.current, track.url != nil, audio.totalTime > 0 else { return }
        audio.clearQueue()
        enqueueNext(after: track)
    }

    private func nowPlayingChanged(_ url: URL?, fromQueue: Bool) {
        guard let url else { return }
        // A faixa começou de verdade: zera as falhas seguidas.
        consecutiveFailures = 0
        // A SFB começou a próxima pré-enfileirada (gapless) ou recomeçou a mesma em "Repetir uma".
        guard let index = GaplessAdvance.index(in: queue, started: url, fromQueue: fromQueue, url: { $0.url }) else { return }
        let restarted = index == queue.currentIndex
        queue = queue.selecting(index: index)
        let track = queue.items[index]
        progress = 0
        if !restarted {
            lastPlayed = track
            currentID = track.id
            selectedID = track.id
            refreshDetails(for: track)
        }
        enqueueNext(after: track)
        saveSession()
        NowPlaying.update(self)
    }

    /// O player tocou tudo o que tinha.
    private func endOfAudio() {
        if currentTrack?.isSegment == true { step(by: 1); return }
        // Próxima não pré-enfileirada (falhou ao abrir, ou é trecho de CUE): segue para ela.
        if let index = queue.nextIndex(), queue.items[index].url != nil {
            queue = queue.selecting(index: index)
            startCurrent()
            return
        }
        // Fim de verdade: com delegate o SFB não para o engine sozinho.
        audio.stop()
        isPlaying = false
        progress = 0
        NowPlaying.update(self)
    }

    /// Arquivo que não abriu ou falhou no meio (aviso assíncrono do SFB).
    private func decodingFailed(_ url: URL?, message: String, ended: Bool) {
        if let url, url == queue.current?.url {
            skipAfterFailure(message)
        } else if ended {
            statusMessage = message
            endOfAudio()
        } else {
            // A próxima pré-enfileirada falhou: a atual segue; no fim, endOfAudio tenta a próxima.
            statusMessage = message
        }
    }

    private func syncEqualizer() {
        audio.applyEqualizer(preamp: preamp, bands: bands, bypass: eqBypass)
        persistEqualizer()
    }

    /// Faixa com erro (arquivo corrompido, sem permissão, ausente): avisa e pula para a próxima.
    func skipAfterFailure(_ message: String) {
        statusMessage = message
        consecutiveFailures += 1
        guard consecutiveFailures < max(queue.items.count, 1),
              let next = queue.withRepeat(repeatMode == .one ? .all : repeatMode).nextIndex() else {
            // Desistiu: nada pode continuar tocando (a faixa anterior seguia se o erro veio antes do play).
            audio.stop()
            isPlaying = false
            consecutiveFailures = 0
            return
        }
        queue = queue.selecting(index: next)
        startCurrentPublic()
    }

    func refreshDetailsPublic(for track: Track) { refreshDetails(for: track) }

    private func refreshDetails(for track: Track) {
        guard let url = track.url else {
            cover = nil
            lyricLines = []
            timedLyrics = nil
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = TrackLoader.cover(for: url)
            let lyrics = TrackLoader.lyricsText(for: url)
            let timed = lyrics.flatMap(LRCParser.parse)
            let lines = timed.map { $0.lines.map(\.text) }
                ?? lyrics.map { $0.split(whereSeparator: \.isNewline).map(String.init) }
            DispatchQueue.main.async {
                guard let self, self.currentID == track.id else { return }
                self.cover = image
                NowPlaying.update(self)
                self.timedLyrics = timed
                let found = lines?.isEmpty == false
                self.lyricLines = found ? lines! : [String(localized: "Letra indisponível\nEsta faixa não tem letra salva.")]
                self.lyricsOrigin = found ? .local(synced: timed != nil) : .none
                if !found, self.lyricsOnline {
                    switch OnlineConsent.answer {
                    case .granted: self.fetchOnlineLyrics(for: track, url: url)
                    case nil: self.lyricsOrigin = .askConsent
                    case .denied: break
                    }
                }
            }
        }
    }

    /// Sem letra local: procura no catálogo online e mostra (sem gravar nada; o painel oferece salvar o .lrc).
    private func fetchOnlineLyrics(for track: Track, url: URL) {
        lyricsOrigin = .searching
        lyricLines = [String(localized: "Procurando a letra…")]
        let duration = track.end.map { $0 - (track.start ?? 0) } ?? Double(track.duration)
        // Na thread principal: estas propriedades redesenham a tela e o menu (fora dela o app fechava).
        Task { @MainActor [weak self] in
            let found = try? await LyricsService.standard().best(title: track.title, artist: track.artist, album: track.album,
                                                       duration: duration > 0 ? duration : nil)
            guard let self, self.currentID == track.id else { return }
            guard let found, let text = found.text else {
                self.lyricsOrigin = .none
                self.lyricLines = [Self.noLyricsMessage]
                return
            }
            let timed = LRCParser.parse(text)
            self.timedLyrics = timed
            self.lyricLines = timed.map { $0.lines.map(\.text) } ?? text.split(whereSeparator: \.isNewline).map(String.init)
            self.lyricsOrigin = .online(found, url: url)
        }
    }

    /// Resposta ao pedido de consentimento mostrado no painel de letras.
    func answerLyricsConsent(_ granted: Bool) {
        OnlineConsent.answer = granted ? .granted : .denied
        if !granted { lyricsOrigin = .none; return }
        if let track = currentTrack, let url = track.url { fetchOnlineLyrics(for: track, url: url) }
    }

    static let noLyricsMessage = String(localized: "Letra indisponível\nEsta faixa não tem letra salva e não a encontramos no nosso catálogo online.")

    /// Grava a letra encontrada online como .lrc ao lado da música.
    func saveOnlineLyrics() {
        guard case .online(let lyrics, let url) = lyricsOrigin, let text = lyrics.text else { return }
        do {
            _ = try LyricsFileWriter.write(text, for: url, replace: false)
            lyricsOrigin = .local(synced: lyrics.isSynced)
        } catch {
            statusMessage = String(localized: "Não foi possível salvar o .lrc")
        }
    }
}

/// Busca da janela: texto digitado e resultados prontos.
final class SearchModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { onChange?(query) } } }
    @Published fileprivate(set) var results: [Track] = [] { didSet { rows = ListRow.rows(results) } }
    /// Linhas dos resultados, montadas junto com eles.
    private(set) var rows: [ListRow] = []
    fileprivate var onChange: ((String) -> Void)?
}

/// Aviso do rodapé e progresso da medição de volume.
final class StatusModel: ObservableObject {
    @Published var message: String?
    @Published var loudnessProgress: (done: Int, total: Int)?
}

/// Volume e curva do EQ (mudam a cada passo de um arrasto).
final class MixerModel: ObservableObject {
    @Published var volume: Double { didSet { onVolume?(volume) } }
    @Published var preamp = 0.0 { didSet { onEqualizer?() } }
    @Published var bands: [Double] = Array(repeating: 0, count: 10) { didSet { onEqualizer?() } }
    fileprivate var onVolume: ((Double) -> Void)?
    fileprivate var onEqualizer: (() -> Void)?

    init(volume: Double) { self.volume = volume }
}

/// Linha ativa da letra.
final class LyricsPosition: ObservableObject {
    @Published var index = 0
}

/// Posição da faixa (0...1), publicada à parte para não redesenhar a lista a cada tick.
final class PlaybackClock: ObservableObject {
    @Published var progress = 0.0
}

/// Faixa selecionada, publicada à parte da lista.
final class SelectionModel: ObservableObject {
    @Published var selectedID: TrackID?
}

/// Origem da letra do painel.
enum LyricsOrigin: Equatable {
    case none, searching, askConsent
    case local(synced: Bool)
    case online(LyricsCandidate, url: URL)
}

extension PlayerState {
    static let correctionLevels: [(name: String, lufs: Double)] = [(String(localized: "Baixo"), -18), (String(localized: "Padrão"), -14), (String(localized: "Alto"), -11)]

    /// Mede o volume das músicas da lista em segundo plano (para a Correção de Som já valer na primeira vez).
    func measureLoudness(of tracks: [Track]) {
        loudnessTask?.cancel()
        let all = Array(Set(tracks.compactMap(\.url)))
        loudnessTask = Task { [weak self] in
            // Consultar o cache faz um stat por música (e carrega o loudness.json): fora da thread principal.
            let urls = await Task.detached(priority: .utility) {
                all.filter { LoudnessAnalyzer.shared.cached($0) == nil }
            }.value
            if Task.isCancelled { return }
            guard !urls.isEmpty else {
                await MainActor.run { self?.statusMessage = String(localized: "Correção de Som: todas estas músicas já estão medidas.") }
                return
            }
            await MainActor.run { self?.loudnessProgress = (0, urls.count) }
            for (n, url) in urls.enumerated() {
                if Task.isCancelled { break }
                _ = await Task.detached(priority: .utility) { LoudnessAnalyzer.shared.measure(url) }.value
                await MainActor.run {
                    self?.loudnessProgress = (n + 1, urls.count)
                    self?.statusMessage = String(localized: "Correção de Som: medindo \(n + 1) de \(urls.count)…")
                }
            }
            await MainActor.run {
                self?.loudnessProgress = nil
                self?.statusMessage = String(localized: "Correção de Som: \(urls.count) músicas medidas.")
            }
        }
    }
}
