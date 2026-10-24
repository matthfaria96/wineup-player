import Foundation
import WineupCore

/// Sessão: lembra a fila inteira, a faixa atual e a posição para retomar ao reabrir.
extension PlayerState {
    private static let sessionPathKey = "session.lastPath"
    private static let sessionPositionKey = "session.lastPosition"
    private static let sessionQueueKey = "session.queuePaths"

    /// Chave existe no disco ("<arquivo.cue>#<n>" confere o arquivo .cue).
    static func keyExists(_ key: String) -> Bool {
        let file = key.range(of: ".cue#").map { String(key[..<key.index($0.lowerBound, offsetBy: 4)]) } ?? key
        return FileManager.default.fileExists(atPath: file)
    }

    func saveSession() {
        guard !Measure.mute, let key = currentTrack?.storeKey else { return }
        UserDefaults.standard.set(key, forKey: Self.sessionPathKey)
        UserDefaults.standard.set(progress, forKey: Self.sessionPositionKey)
        let paths = queue.items.prefix(2000).compactMap(\.storeKey)
        UserDefaults.standard.set(paths, forKey: Self.sessionQueueKey)
    }

    /// Restaura a fila e a última faixa (sem tocar), prontas na posição salva.
    /// Disco e banco são lidos fora da thread principal; o resultado volta para ela.
    func restoreSession(in list: [Track]) {
        guard queue.current == nil,
              let path = UserDefaults.standard.string(forKey: Self.sessionPathKey) else { return }
        let saved = UserDefaults.standard.stringArray(forKey: Self.sessionQueueKey) ?? []
        let position = UserDefaults.standard.double(forKey: Self.sessionPositionKey)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard Self.keyExists(path) else { return }
            let plan = Self.restorePlan(path: path, saved: saved.filter(Self.keyExists), list: list)
            DispatchQueue.main.async {
                guard let self else { return }
                self.browser.tracks(atPaths: plan.lookups) { found in
                    self.applyRestore(plan, found: found, list: list, position: position)
                }
            }
        }
    }

    /// O que restaurar: a fila salva (ou a lista, ou só a faixa) e os caminhos a buscar no banco.
    struct RestorePlan {
        let id: TrackID
        let savedPaths: [String]
        let lookups: [String]
        let useSaved: Bool
        let useList: Bool
    }

    private static func trackID(_ path: String) -> TrackID {
        TrackID(stableKey: URL(fileURLWithPath: path).standardizedFileURL.path)
    }

    private static func restorePlan(path: String, saved: [String], list: [Track]) -> RestorePlan {
        let id = trackID(path)
        let known = Set(list.map(\.id))
        let useSaved = saved.contains { trackID($0) == id }
        let useList = !useSaved && known.contains(id)
        let lookups = useSaved ? saved.filter { !known.contains(trackID($0)) } : (useList ? [] : [path])
        return RestorePlan(id: id, savedPaths: saved, lookups: lookups, useSaved: useSaved, useList: useList)
    }

    private func applyRestore(_ plan: RestorePlan, found: [Track], list: [Track], position: Double) {
        // O usuário já começou a tocar algo: não substitui a fila dele.
        guard queue.current == nil, currentID == nil else { return }
        let source: [Track]
        if plan.useSaved {
            let byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var extra = found.makeIterator()
            source = plan.savedPaths.compactMap { byID[Self.trackID($0)] ?? extra.next() }
        } else {
            source = plan.useList ? list : found
        }
        guard let index = source.firstIndex(where: { $0.id == plan.id }) else { return }
        queue = PlaybackQueue(items: source, currentIndex: index).withRepeat(repeatMode)
        let track = source[index]
        lastPlayed = track
        currentID = track.id
        selectedID = track.id
        progress = position
        resumeFraction = position
        refreshDetailsPublic(for: track)
    }
}
