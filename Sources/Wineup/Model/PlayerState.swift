import AppKit
import Foundation

/// Estado do player. Faixas com `url` tocam de verdade; as de exemplo (sem url) só animam a interface.
final class PlayerState: ObservableObject {
    @Published var tracks: [Track] = SampleData.tracks
    @Published var currentID: Int = 17
    @Published var selectedID: Int?
    @Published var isPlaying = false
    @Published var progress = 0.0
    @Published var balance = 0.5
    @Published var speed = 0.5
    @Published var eqBypass = false { didSet { syncEqualizer() } }
    @Published var preset = "Custom"
    @Published var query = ""
    @Published var markFilter: MarkColor?
    @Published var lyricsScale = 1.0
    @Published var cover: NSImage?
    @Published var lyricLines: [String] = SampleData.lyrics
    @Published var statusMessage: String?

    @Published var volume = 0.8 { didSet { audio.setVolume(volume) } }
    @Published var preamp = 0.0 { didSet { syncEqualizer() } }
    @Published var bands: [Double] = SampleData.presets["Custom"] ?? [] { didSet { syncEqualizer() } }

    private let audio = AudioEngineService()

    init() {
        audio.onEndOfAudio = { [weak self] in self?.step(by: 1) }
        audio.onError = { [weak self] message in self?.statusMessage = message }
        audio.setVolume(volume)
        syncEqualizer()
    }

    var currentTrack: Track? { tracks.first { $0.id == currentID } }

    var visibleTracks: [Track] {
        guard let markFilter else { return tracks }
        return tracks.filter { $0.mark == markFilter }
    }

    var searchResults: [Track] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return tracks.filter { $0.displayName.localizedCaseInsensitiveContains(needle) }
    }

    var remainingSeconds: Int {
        guard let track = currentTrack else { return 0 }
        return Int(Double(track.duration) * (1 - progress))
    }

    var activeLyricIndex: Int {
        guard !lyricLines.isEmpty else { return 0 }
        return min(Int(progress * Double(lyricLines.count)), lyricLines.count - 1)
    }

    // MARK: Biblioteca

    func load(urls: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = TrackLoader.tracks(from: urls)
            DispatchQueue.main.async {
                guard let self else { return }
                guard !loaded.isEmpty else {
                    self.statusMessage = "Nenhum áudio suportado encontrado."
                    return
                }
                self.stop()
                self.tracks = loaded
                self.currentID = loaded[0].id
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
        currentID = track.id
        selectedID = track.id
        progress = 0
        refreshDetails(for: track)
        if let url = track.url {
            do {
                try audio.play(url)
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
        guard let index = tracks.firstIndex(where: { $0.id == currentID }), !tracks.isEmpty else { return }
        play(tracks[(index + offset + tracks.count) % tracks.count])
    }

    func playRandom() {
        if let track = tracks.randomElement() { play(track) }
    }

    func deleteSelected() {
        guard let selectedID else { return }
        tracks = tracks.filter { $0.id != selectedID }
        self.selectedID = nil
    }

    func tick(_ delta: Double) {
        guard isPlaying, let track = currentTrack else { return }
        if track.url != nil {
            let total = audio.totalTime
            if total > 0 { progress = min(audio.currentTime / total, 1) }
        } else if track.duration > 0 {
            let next = progress + delta / Double(track.duration)
            if next >= 1 { step(by: 1) } else { progress = next }
        }
    }

    func apply(preset name: String) {
        preset = name
        bands = SampleData.presets[name] ?? bands
    }

    // MARK: Privado

    private func syncEqualizer() {
        audio.applyEqualizer(preamp: preamp, bands: bands, bypass: eqBypass)
    }

    private func refreshDetails(for track: Track) {
        guard let url = track.url else {
            cover = nil
            lyricLines = SampleData.lyrics
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
