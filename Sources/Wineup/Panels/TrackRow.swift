import AppKit
import WineupCore
import SwiftUI

/// Linha de faixa usada na playlist e na busca.
struct TrackRow: View {
    private var rowBackground: Color {
        if isCurrent { return theme.currentRow.opacity(0.16) }
        if isSelected { return theme.rowSelection }
        return index % 2 == 0 ? Color.white.opacity(0.025) : Color.clear
    }

    let track: Track
    let index: Int
    let isCurrent: Bool
    let isSelected: Bool
    var showsDuration = true
    var detailed = false

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            if detailed {
                RowCover(url: track.url)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).lineLimit(1)
                    Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(theme.mutedText).lineLimit(1)
                }
            } else {
                Text("\(index)")
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(isCurrent ? theme.currentRow : theme.mutedText)
                    .frame(width: 28, alignment: .trailing)
                Text(track.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if showsDuration {
                if let mark = track.mark {
                    Circle().fill(mark.color).frame(width: 7, height: 7)
                }
                Text(Clock.format(track.duration))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? theme.currentRow : theme.mutedText)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(isCurrent ? theme.currentRow : theme.text)
        .padding(.horizontal, 14)
        .frame(height: detailed ? 40 : 29)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isCurrent { Rectangle().fill(theme.currentRow).frame(width: 3) }
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}

/// Miniatura da capa no modo "Com detalhes" (nota musical enquanto carrega ou sem capa).
private struct RowCover: View {
    let url: URL?
    @StateObject private var covers = CoverLoader()
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 4).fill(theme.artworkTint)
            .frame(width: 30, height: 30)
            .overlay {
                if let image = covers.image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onAppear { covers.load(url) }
            .onDisappear { covers.cancel() }
    }
}

/// Bloco da lista em grade.
struct TrackTile: View {
    let track: Track
    let isCurrent: Bool
    @StateObject private var covers = CoverLoader()
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 6).fill(theme.artworkTint)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let image = covers.image {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.black.opacity(0.3))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if let mark = track.mark { Circle().fill(mark.color).frame(width: 10, height: 10).padding(6) }
            }
            Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(track.artist).font(.system(size: 10)).foregroundStyle(theme.mutedText).lineLimit(1)
        }
        .foregroundStyle(isCurrent ? theme.currentRow : theme.text)
        .onAppear { covers.load(track.url) }
        .onDisappear { covers.cancel() }
    }
}

/// Carrega a capa embutida de uma faixa fora da main thread, com cache em memória.
final class CoverLoader: ObservableObject {
    @Published var image: NSImage?
    private var requested: URL?
    private var waiter: CoverQueue.Waiter?

    func load(_ url: URL?) {
        guard image == nil, let url, requested != url else { return }
        requested = url
        waiter = CoverQueue.shared.request(url) { [weak self] found in
            self?.waiter = nil
            if let found { self?.image = found }
        }
    }

    /// A linha saiu da tela: desiste do pedido (se ninguém mais espera a mesma capa, ele é cancelado).
    func cancel() {
        if let waiter { CoverQueue.shared.cancel(waiter) }
        waiter = nil
        requested = nil
    }

    deinit {
        if let waiter { CoverQueue.shared.cancel(waiter) }
    }
}

/// Fila única das miniaturas: no máximo 4 leituras ao mesmo tempo, pedidos iguais juntos,
/// cache com limite de memória. Toda a contabilidade roda na thread principal.
final class CoverQueue {
    static let shared = CoverQueue()

    final class Waiter {
        let url: URL
        let done: (NSImage?) -> Void
        init(url: URL, done: @escaping (NSImage?) -> Void) { self.url = url; self.done = done }
    }

    private struct Pending {
        var waiters: [Waiter]
        let operation: Operation
    }

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .utility
        return queue
    }()
    /// Cache de miniaturas com limite de memória (~40 MB) e de quantidade.
    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = 40 * 1024 * 1024
        cache.countLimit = 600
        return cache
    }()
    /// Faixas sem capa (não relê o arquivo a cada vez que a linha aparece).
    private let misses = NSCache<NSURL, NSNumber>()
    private var pending: [URL: Pending] = [:]

    /// Pede a miniatura; `done` roda na thread principal. Devolve nil quando já respondeu na hora.
    func request(_ url: URL, done: @escaping (NSImage?) -> Void) -> Waiter? {
        if let cached = cache.object(forKey: url as NSURL) { done(cached); return nil }
        if misses.object(forKey: url as NSURL) != nil { done(nil); return nil }
        let waiter = Waiter(url: url, done: done)
        if pending[url] != nil {
            pending[url]?.waiters.append(waiter)
            return waiter
        }
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation, weak self] in
            guard operation?.isCancelled == false else { return }
            let found = TrackLoader.thumbnail(for: url)
            DispatchQueue.main.async { self?.finish(url, image: found) }
        }
        pending[url] = Pending(waiters: [waiter], operation: operation)
        queue.addOperation(operation)
        return waiter
    }

    func cancel(_ waiter: Waiter) {
        guard var entry = pending[waiter.url] else { return }
        entry.waiters.removeAll { $0 === waiter }
        if entry.waiters.isEmpty {
            entry.operation.cancel()
            pending[waiter.url] = nil
        } else {
            pending[waiter.url] = entry
        }
    }

    private func finish(_ url: URL, image: NSImage?) {
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4))
        } else {
            misses.setObject(true, forKey: url as NSURL)
        }
        let waiters = pending.removeValue(forKey: url)?.waiters ?? []
        for waiter in waiters { waiter.done(image) }
    }
}

/// Menu de contexto da faixa: tag de cor e playlists.
struct TrackMenu: View {
    let state: PlayerState
    let track: Track

    var body: some View {
        Button("Tocar") { state.play(track, from: state.visibleTracks) }
        Button("Tocar a seguir") { state.playNext(track) }
        if state.browser.view == .queue {
            Button("Remover da fila") { state.removeFromQueue(track) }
        }
        Button(state.browser.openPlaylistID != nil ? "Remover da playlist" : "Remover da lista") {
            state.removeFromList(track)
        }
        Menu("Tag de cor") {
            ForEach(MarkColor.allCases) { color in
                Button(color.displayName) { state.setMark(color, on: track) }
            }
            Divider()
            Button("Remover tag") { state.setMark(nil, on: track) }
        }
        Menu("Adicionar à playlist") {
            ForEach(state.browser.playlists) { list in
                Button(list.name) { state.addToPlaylist(track, playlistID: list.id) }
            }
            Divider()
            Button("Nova playlist com esta faixa") { state.newPlaylist(with: track) }
        }
    }
}

/// Linha que observa só a seleção (o painel não redesenha a lista ao selecionar).
struct SelectableTrackRow: View {
    @ObservedObject var selection: SelectionModel
    let track: Track
    let index: Int
    let isCurrent: Bool
    var detailed = false

    var body: some View {
        TrackRow(track: track, index: index, isCurrent: isCurrent,
                 isSelected: selection.selectedID == track.id, detailed: detailed)
    }
}
