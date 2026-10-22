import Foundation
import WineupCore

/// Sessão: lembra a fila inteira, a faixa atual e a posição para retomar ao reabrir.
extension PlayerState {
    private static let sessionPathKey = "session.lastPath"
    private static let sessionPositionKey = "session.lastPosition"
    private static let sessionQueueKey = "session.queuePaths"

    func saveSession() {
        guard let url = currentTrack?.url else { return }
        UserDefaults.standard.set(url.path, forKey: Self.sessionPathKey)
        UserDefaults.standard.set(progress, forKey: Self.sessionPositionKey)
        let paths = queue.items.prefix(2000).compactMap { $0.url?.path }
        UserDefaults.standard.set(paths, forKey: Self.sessionQueueKey)
    }

    /// Restaura a fila e a última faixa (sem tocar), prontas na posição salva.
    func restoreSession(in list: [Track]) {
        guard queue.current == nil,
              let path = UserDefaults.standard.string(forKey: Self.sessionPathKey),
              FileManager.default.fileExists(atPath: path) else { return }
        let id = TrackID(stableKey: URL(fileURLWithPath: path).standardizedFileURL.path)
        let savedPaths = (UserDefaults.standard.stringArray(forKey: Self.sessionQueueKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
        let byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let restored = savedPaths.map { p -> Track in
            let key = TrackID(stableKey: URL(fileURLWithPath: p).standardizedFileURL.path)
            return byID[key] ?? browser.track(atPath: p)
        }
        let source = restored.contains { $0.id == id } ? restored
            : (list.contains { $0.id == id } ? list : [TrackLoader.track(url: URL(fileURLWithPath: path))])
        guard let index = source.firstIndex(where: { $0.id == id }) else { return }
        queue = PlaybackQueue(items: source, currentIndex: index).withRepeat(repeatMode)
        let track = source[index]
        lastPlayed = track
        currentID = track.id
        selectedID = track.id
        let position = UserDefaults.standard.double(forKey: Self.sessionPositionKey)
        progress = position
        resumeFraction = position
        refreshDetailsPublic(for: track)
    }
}
