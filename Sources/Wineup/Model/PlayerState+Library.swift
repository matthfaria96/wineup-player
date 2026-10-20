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
