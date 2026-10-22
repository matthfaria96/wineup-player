import Foundation
import WineupCore
import WineupLibrary

extension PlayerState {
    func showGroup(title: String, items: [LibraryTrack]) {
        listTitle = title
        tracks = items.map(track(from:))
        selectedID = nil
    }

    func setMark(_ color: MarkColor?, on track: Track) {
        guard let url = track.url else { return }
        browser.setMark(color, path: url.path)
        let replaced = Track(id: track.id, artist: track.artist, title: track.title, duration: track.duration,
                             mark: color, url: track.url, album: track.album, year: track.year)
        tracks = tracks.map { $0.id == track.id ? replaced : $0 }
    }

    func addToPlaylist(_ track: Track, playlistID: Int64) {
        guard let url = track.url else { return }
        browser.add(paths: [url.path], toPlaylist: playlistID)
    }

    /// Pede o nome e cria a playlist (opcionalmente já com uma faixa).
    func newPlaylist(with track: Track?) {
        guard let name = TextPrompt.ask(title: "Nova playlist", value: "Nova playlist") else { return }
        if let created = browser.createPlaylist(named: name, paths: track?.url.map { [$0.path] } ?? []) {
            statusMessage = "Playlist \u{201C}\(created.name)\u{201D} criada."
        }
    }

    /// Remove a faixa da playlist aberta (no banco) ou só da lista atual.
    func removeFromList(_ track: Track) {
        if let id = browser.openPlaylistID, let url = track.url {
            browser.remove(path: url.path, fromPlaylist: id)
            tracks = tracks.filter { $0.id != track.id }
        } else {
            tracks = tracks.filter { $0.id != track.id }
        }
        if selectedID == track.id { selectedID = nil }
    }

    func playSelected() {
        let pick = selectedID.flatMap { id in visibleTracks.first { $0.id == id } } ?? visibleTracks.first
        if let pick { play(pick, from: visibleTracks) }
    }

    func removeSelected() {
        guard let id = selectedID, let track = tracks.first(where: { $0.id == id }) else { return }
        removeFromList(track)
    }
}

extension PlayerState {
    /// Abre a pasta na lista e toca a primeira faixa.
    func playFolder(_ url: URL) {
        browser.goFolder(url)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let first = TrackLoader.audioURLs(in: [url]).first.map(TrackLoader.track(url:))
            DispatchQueue.main.async {
                guard let self, let first else { return }
                let match = self.tracks.first { $0.url == first.url } ?? first
                self.play(match)
            }
        }
    }
}

extension PlayerState {
    /// Coloca a faixa logo depois da que está tocando.
    func playNext(_ track: Track) {
        guard let current = queue.currentIndex else { play(track, from: visibleTracks); return }
        queue = queue.inserting([track], at: current + 1)
        reenqueue()
        statusMessage = "\u{201C}\(track.title)\u{201D} toca a seguir."
    }

    /// Abre todas as músicas da biblioteca na lista.
    func showAllTracks() {
        browser.open(BrowseGroup(kind: .allTracks, title: "Todas as músicas", subtitle: "", count: 0))
    }
}
