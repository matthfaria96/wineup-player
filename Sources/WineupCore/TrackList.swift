import Foundation

public enum TrackList {
    public static func removing(_ id: TrackID, from tracks: [Track]) -> [Track] {
        tracks.filter { $0.id != id }
    }

    public static func neighbor(of id: TrackID, offset: Int, in tracks: [Track]) -> Track? {
        guard !tracks.isEmpty, let index = tracks.firstIndex(where: { $0.id == id }) else { return nil }
        return tracks[((index + offset) % tracks.count + tracks.count) % tracks.count]
    }
}
