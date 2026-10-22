import Foundation
import WineupCore

/// Sessão: lembra a última faixa e a posição para retomar ao reabrir o app.
extension PlayerState {
    private static let sessionPathKey = "session.lastPath"
    private static let sessionPositionKey = "session.lastPosition"

    func saveSession() {
        guard let url = currentTrack?.url else { return }
        UserDefaults.standard.set(url.path, forKey: Self.sessionPathKey)
        UserDefaults.standard.set(progress, forKey: Self.sessionPositionKey)
    }

    /// Restaura a última faixa (sem tocar): fica pronta no player, na posição salva.
    func restoreSession(in list: [Track]) {
        guard queue.current == nil,
              let path = UserDefaults.standard.string(forKey: Self.sessionPathKey),
              FileManager.default.fileExists(atPath: path) else { return }
        let id = TrackID(stableKey: URL(fileURLWithPath: path).standardizedFileURL.path)
        let track = list.first { $0.id == id } ?? TrackLoader.track(url: URL(fileURLWithPath: path))
        let source = list.contains { $0.id == id } ? list : [track]
        queue = PlaybackQueue(items: source, currentIndex: source.firstIndex { $0.id == id } ?? 0).withRepeat(repeatMode)
        lastPlayed = track
        currentID = track.id
        selectedID = track.id
        let position = UserDefaults.standard.double(forKey: Self.sessionPositionKey)
        progress = position
        resumeFraction = position
        refreshDetailsPublic(for: track)
    }
}
