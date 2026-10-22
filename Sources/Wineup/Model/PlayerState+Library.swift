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

    func newPlaylist(with track: Track?) {
        browser.createPlaylist(named: "Nova playlist", paths: track?.url.map { [$0.path] } ?? [])
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
