import AppKit
import Foundation
import WineupAudio
import WineupCore
import WineupLibrary

/// Estado do player. Faixas com `url` tocam de verdade; as de exemplo (sem url) só animam a interface.
final class PlayerState: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var currentID: TrackID?
    @Published var selectedID: TrackID?
    @Published var isPlaying = false
    @Published var progress = 0.0
    @Published var balance = PlayerState.saved("balance", 0.5) {
        didSet { audio.setBalance(RateMapping.pan(balance: balance)); UserDefaults.standard.set(balance, forKey: "balance") }
    }
    @Published var speed = PlayerState.saved("speed", 0.5) {
        didSet { audio.setRate(RateMapping.rate(slider: speed)); UserDefaults.standard.set(speed, forKey: "speed") }
    }
    /// Fila de reprodução: a lista de onde a música foi tocada (navegar não interrompe a sequência).
    @Published var queue = PlaybackQueue<Track>()
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
    @Published var outputSampleRate: Double?
    @Published var eqBypass = false { didSet { syncEqualizer() } }
    @Published var preset = "Custom"
    @Published var presets: [EqPreset] = EqPreset.builtIns
    @Published var query = "" { didSet { scheduleLibrarySearch() } }
    @Published var libraryResults: [Track] = []
    @Published var markFilter: MarkColor?
    @Published var lyricsScale = 1.0
    @Published var cover: NSImage?
    @Published var lyricLines: [String] = []
    @Published var statusMessage: String?
    /// Nome do que está na lista agora (álbum, banda, pasta, estilo ou playlist).
    @Published var listTitle = "Playlist"
    @Published var listStyle: ListStyle = ListStyle(rawValue: UserDefaults.standard.string(forKey: DisplayKeys.listStyle) ?? "") ?? .compact {
        didSet { UserDefaults.standard.set(listStyle.rawValue, forKey: DisplayKeys.listStyle) }
    }

    @Published var volume = PlayerState.saved("volume", 0.8) {
        didSet { audio.setVolume(volume); UserDefaults.standard.set(volume, forKey: "volume") }
    }

    static func saved(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }
    @Published var preamp = 0.0 { didSet { syncEqualizer() } }
    @Published var bands: [Double] = SampleData.presets["Custom"] ?? [] { didSet { syncEqualizer() } }

    private let audio = SFBAudioEngineAdapter()
    let library = LibraryController()
    let browser: LibraryBrowser
    /// Última faixa tocada, para o player continuar mostrando-a quando a lista muda de grupo.
    var lastPlayed: Track?
    private var searchTask: Task<Void, Never>?
    private var usingSampleTracks = true
    private var restoredOnce = false
    private var eqSaveTask: Task<Void, Never>?

    init() {
        browser = LibraryBrowser(database: library.database)
        audio.onNowPlayingChanged = { [weak self] url in self?.nowPlayingChanged(url) }
        audio.onEndOfAudio = { [weak self] in
            self?.isPlaying = false
            self?.progress = 0
        }
        audio.onError = { [weak self] message in self?.statusMessage = message }
        audio.onConfigurationChange = { [weak self] rate in self?.outputSampleRate = rate }
        audio.setVolume(volume)
        audio.setRate(RateMapping.rate(slider: speed))
        audio.setBalance(RateMapping.pan(balance: balance))
        audio.replayGainMode = replayGainMode
        audio.preventClipping = preventClipping
        restoreEqualizer()
        syncEqualizer()
        browser.onShowTracks = { [weak self] title, items in self?.showTracks(title: title, items: items) }
        browser.onRescan = { [weak self] in Task { @MainActor in self?.library.rescan() } }
        NowPlaying.attach(self)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.saveSession() }
    }

    var meter: LevelTap { audio.meter }

    var playbackRate: Double { RateMapping.rate(slider: speed) }

    var currentTrack: Track? {
        queue.current ?? tracks.first { $0.id == currentID } ?? lastPlayed.flatMap { $0.id == currentID ? $0 : nil }
    }

    /// Posição 1-based da faixa atual na lista.
    var currentPosition: Int? { tracks.firstIndex { $0.id == currentID }.map { $0 + 1 } }

    var visibleTracks: [Track] {
        guard let markFilter else { return tracks }
        return tracks.filter { $0.mark == markFilter }
    }

    var searchResults: [Track] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        if library.isAvailable, !libraryResults.isEmpty { return libraryResults }
        // Sem resultado na biblioteca (ou fora dela): filtra a lista aberta.
        return tracks.filter { $0.displayName.localizedCaseInsensitiveContains(needle) }
    }

    var remainingSeconds: Int {
        guard let track = currentTrack else { return 0 }
        if track.url != nil, audio.totalTime > 0 {
            return Int(RateMapping.remainingWallSeconds(
                total: audio.totalTime, current: audio.currentTime, rate: playbackRate))
        }
        return Int(Double(track.duration) * (1 - progress) / playbackRate)
    }

    var activeLyricIndex: Int {
        guard !lyricLines.isEmpty else { return 0 }
        return min(Int(progress * Double(lyricLines.count)), lyricLines.count - 1)
    }

    // MARK: Biblioteca

    func startLibrary() async {
        await library.start(
            onTracks: { [weak self] found in self?.applyLibraryTracks(found) },
            onStatus: { [weak self] message in self?.statusMessage = message })
    }

    /// A biblioteca carregou/terminou uma varredura.
    private func applyLibraryTracks(_ found: [LibraryTrack]) {
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
        listTitle = title
        tracks = items
        selectedID = nil
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

    private func loadFiles(_ urls: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = TrackLoader.tracks(from: urls)
            DispatchQueue.main.async {
                guard let self else { return }
                guard !loaded.isEmpty else {
                    self.statusMessage = "Nenhum áudio suportado encontrado."
                    return
                }
                self.stop()
                self.usingSampleTracks = false
                self.tracks = loaded
                self.currentID = loaded.first?.id
                self.selectedID = nil
                self.statusMessage = nil
                self.play(loaded[0])
            }
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Escolha arquivos de áudio ou pastas de música"
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

    /// Toca o item atual da fila (sem remontá-la).
    private func startCurrent(resumeAt fraction: Double? = nil) {
        guard let track = queue.current else { return }
        lastPlayed = track
        currentID = track.id
        selectedID = track.id
        progress = 0
        refreshDetails(for: track)
        if let url = track.url {
            do {
                try audio.play(url)
                if let fraction, fraction > 0 { audio.seek(toFraction: fraction) }
                enqueueNext(after: track)
                isPlaying = true
                statusMessage = nil
                saveSession()
                NowPlaying.update(self)
            } catch {
                isPlaying = false
                statusMessage = "Não foi possível tocar \(track.title): \(error.localizedDescription)"
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
        if currentTrack?.url != nil { audio.seek(toFraction: progress) }
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
            if total > 0 { progress = min(audio.currentTime / total, 1) }
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
        guard let store = library.presetStore else { statusMessage = "Biblioteca indisponível para salvar presets."; return }
        guard let valid = EqPreset.validated(name: name, preamp: preamp, bands: bands) else {
            statusMessage = "Nome de preset inválido (1 a \(EqPreset.maxNameLength) caracteres)."
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
        case .duplicateName: return "Já existe um preset com esse nome."
        case .reservedName: return "Esse nome é reservado a um preset embutido."
        case .notFound: return "Preset não encontrado."
        default: return "Não foi possível salvar o preset."
        }
    }

    private func restoreEqualizer() {
        guard let store = library.presetStore else { return }
        reloadPresets(store)
        guard let saved = store.loadCurrent() else { return }
        preamp = saved.preamp
        bands = saved.bands
        eqBypass = saved.bypass
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
        guard let index = queue.nextIndex(), let url = queue.items[index].url else { return }
        try? audio.enqueue(url)
    }

    /// Refaz o pré-enfileiramento quando repetir/aleatório mudam.
    func reenqueue() {
        guard let track = queue.current, isPlaying else { return }
        audio.clearQueue()
        enqueueNext(after: track)
    }

    private func nowPlayingChanged(_ url: URL?) {
        guard let url, queue.current?.url != url else { return }
        // A SFB começou a próxima faixa pré-enfileirada (gapless): avança a fila.
        guard let index = queue.nextIndex(), queue.items[index].url == url else { return }
        queue = queue.selecting(index: index)
        let track = queue.items[index]
        lastPlayed = track
        currentID = track.id
        selectedID = track.id
        progress = 0
        refreshDetails(for: track)
        enqueueNext(after: track)
        saveSession()
        NowPlaying.update(self)
    }

    private func syncEqualizer() {
        audio.applyEqualizer(preamp: preamp, bands: bands, bypass: eqBypass)
        persistEqualizer()
    }

    func refreshDetailsPublic(for track: Track) { refreshDetails(for: track) }

    private func refreshDetails(for track: Track) {
        guard let url = track.url else {
            cover = nil
            lyricLines = []
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = TrackLoader.cover(for: url)
            let lines = TrackLoader.lyrics(for: url)
            DispatchQueue.main.async {
                guard let self, self.currentID == track.id else { return }
                self.cover = image
                NowPlaying.update(self)
                self.lyricLines = lines ?? ["Sem letra nesta faixa"]
            }
        }
    }
}
