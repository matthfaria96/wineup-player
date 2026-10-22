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
    @Published var balance = 0.5 { didSet { audio.setBalance(RateMapping.pan(balance: balance)) } }
    @Published var speed = 0.5 { didSet { audio.setRate(RateMapping.rate(slider: speed)) } }
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

    @Published var volume = 0.8 { didSet { audio.setVolume(volume) } }
    @Published var preamp = 0.0 { didSet { syncEqualizer() } }
    @Published var bands: [Double] = SampleData.presets["Custom"] ?? [] { didSet { syncEqualizer() } }

    private let audio = SFBAudioEngineAdapter()
    let library = LibraryController()
    let browser: LibraryBrowser
    /// Última faixa tocada, para o player continuar mostrando-a quando a lista muda de grupo.
    var lastPlayed: Track?
    private var searchTask: Task<Void, Never>?
    private var usingSampleTracks = true
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
        browser.onOpen = { [weak self] title, items in self?.showGroup(title: title, items: items) }
        browser.onRefresh = { [weak self] in
            Task { @MainActor in self?.library.rescan() }
        }
        browser.onOpenTracks = { [weak self] title, items in
            guard let self else { return }
            self.listTitle = title
            self.tracks = items.map { t in
                Track(id: t.id, artist: t.artist, title: t.title, duration: t.duration,
                      mark: self.browser.mark(for: t.url), url: t.url, album: t.album, year: t.year)
            }
            self.selectedID = nil
        }
    }

    var meter: LevelTap { audio.meter }

    var playbackRate: Double { RateMapping.rate(slider: speed) }

    var currentTrack: Track? {
        tracks.first { $0.id == currentID } ?? lastPlayed.flatMap { $0.id == currentID ? $0 : nil }
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
        if track.url != nil {
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

    private func applyLibraryTracks(_ found: [LibraryTrack]) {
        browser.refreshMarks()
        browser.reload()
        guard usingSampleTracks else { return }
        guard !found.isEmpty else {
            // Biblioteca ainda vazia: começa navegando a pasta Música do usuário.
            usingSampleTracks = false
            browser.goFolder(NavPlaces.music)
            return
        }
        let mapped = found.map(track(from:))
        usingSampleTracks = false
        listTitle = "Todas as músicas"
        browser.currentGroupTitle = "Todas as músicas"
        tracks = mapped
        selectedID = nil
        // Automação/testes: WINEUP_AUTOPLAY=1 toca a primeira faixa ao abrir.
        if ProcessInfo.processInfo.environment["WINEUP_AUTOPLAY"] != nil, let first = mapped.first { play(first) }
    }

    func track(from item: LibraryTrack) -> Track {
        Track(artist: item.artist, title: item.title, duration: Int(item.duration ?? 0),
              mark: browser.mark(for: item.url), url: item.url, album: item.album)
    }

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

    func play(_ track: Track) {
        lastPlayed = track
        currentID = track.id
        selectedID = track.id
        progress = 0
        refreshDetails(for: track)
        if let url = track.url {
            do {
                try audio.play(url)
                enqueueNext(after: track)
                isPlaying = true
                statusMessage = nil
            } catch {
                isPlaying = false
                statusMessage = "Não foi possível tocar \(track.title): \(error.localizedDescription)"
            }
        } else {
            isPlaying = true
        }
    }

    func togglePlay() {
        guard let track = currentTrack else { return }
        if track.url == nil { isPlaying.toggle(); return }
        if isPlaying {
            audio.pause()
            isPlaying = false
        } else if audio.currentTime > 0 {
            audio.resume()
            isPlaying = true
        } else {
            play(track)
        }
    }

    func pause() {
        if currentTrack?.url != nil { audio.pause() }
        isPlaying = false
    }

    func stop() {
        audio.stop()
        isPlaying = false
        progress = 0
    }

    func seek(to fraction: Double) {
        progress = min(max(fraction, 0), 1)
        if currentTrack?.url != nil { audio.seek(toFraction: progress) }
    }

    func step(by offset: Int) {
        guard let currentID, let next = TrackList.neighbor(of: currentID, offset: offset, in: tracks) else { return }
        play(next)
    }

    func playRandom() {
        if let track = tracks.randomElement() { play(track) }
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
        guard let next = NextTrackPlanner.next(after: track.id, in: tracks), let url = next.url else { return }
        try? audio.enqueue(url)
    }

    private func nowPlayingChanged(_ url: URL?) {
        guard let url else { return }
        let current = currentID.flatMap { id in tracks.firstIndex { $0.id == id } } ?? -1
        let matches = tracks.indices.filter { tracks[$0].url == url }
        guard let index = matches.first(where: { $0 > current }) ?? matches.first else { return }
        let track = tracks[index]
        guard track.id != currentID else { return }
        currentID = track.id
        selectedID = track.id
        progress = 0
        refreshDetails(for: track)
        enqueueNext(after: track)
    }

    private func syncEqualizer() {
        audio.applyEqualizer(preamp: preamp, bands: bands, bypass: eqBypass)
        persistEqualizer()
    }

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
                self.lyricLines = lines ?? ["Sem letra nesta faixa"]
            }
        }
    }
}
