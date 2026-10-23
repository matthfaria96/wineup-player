import SwiftUI
import WineupCore
import WineupLibrary

/// Página do artista (grupo aberto na visão Artistas): cabeçalho com Reproduzir tudo / Embaralhar,
/// ordenação visível e os lançamentos (álbuns, EPs e "Singles") como cartões; a lista abaixo mostra
/// todas as músicas ou só as do lançamento escolhido. Nada é regravado nos arquivos.
struct ArtistHeader: View {
    @ObservedObject var state: PlayerState
    let artist: String
    let tracks: [Track]
    @Binding var release: String?
    @AppStorage("artist.order") private var orderRaw = ArtistOrder.byAlbum.rawValue
    @AppStorage("playback.dedupePlayAll") private var dedupe = true
    @Environment(\.theme) private var theme

    var order: ArtistOrder { ArtistOrder(rawValue: orderRaw) ?? .byAlbum }

    /// Lançamentos do artista: álbuns com mais de uma faixa; o resto vai para "Singles".
    var releases: [(name: String, tracks: [Track], year: String?)] {
        let byAlbum = Dictionary(grouping: tracks) { ($0.album ?? "").trimmingCharacters(in: .whitespaces) }
        var singles: [Track] = []
        var out: [(String, [Track], String?)] = []
        for (name, items) in byAlbum {
            if name.isEmpty || name == "Unknown Album" || items.count == 1 { singles += items; continue }
            out.append((name, items, items.compactMap(\.year).min().map { String($0.prefix(4)) }))
        }
        out.sort { ($0.2 ?? "9999", $0.0) < ($1.2 ?? "9999", $1.0) }
        if !singles.isEmpty { out.append((BrowseService.singlesTitle, singles, nil)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist).font(.system(size: 20, weight: .bold)).lineLimit(1)
                    Text("\(releases.count) lançamento\(releases.count == 1 ? "" : "s") · \(tracks.count) música\(tracks.count == 1 ? "" : "s")")
                        .font(.system(size: 11)).foregroundStyle(theme.mutedText)
                }
                Spacer()
                ChromeButton(action: playAll) { Label("Reproduzir tudo", systemImage: "play.fill").labelStyle(.titleAndIcon) }
                    .fixedSize()
                    .help("Tocar tudo do artista na ordem \(order.title.lowercased())")
                ChromeButton(action: shuffle) { Label("Embaralhar", systemImage: "shuffle").labelStyle(.titleAndIcon) }
                    .fixedSize()
                    .help("Tocar tudo do artista em ordem aleatória")
                Menu {
                    Picker("Ordem", selection: $orderRaw) {
                        ForEach(ArtistOrder.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                    Toggle("Não repetir a mesma música de single e álbum", isOn: $dedupe)
                } label: {
                    Label(order.title, systemImage: "arrow.up.arrow.down").labelStyle(.titleAndIcon)
                }
                .skinMenuChrome()
                .help("Ordem de Reproduzir tudo e da lista")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    card(name: nil, title: "Todas as músicas", subtitle: "\(tracks.count) faixas", cover: tracks.first?.url)
                    ForEach(releases, id: \.name) { r in
                        card(name: r.name, title: r.name, subtitle: [r.year, "\(r.tracks.count) faixas"].compactMap { $0 }.joined(separator: " · "),
                             cover: r.tracks.first?.url)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Faixas mostradas na lista (todas na ordem escolhida, ou só do lançamento escolhido).
    func listed() -> [Track] {
        if let release, let r = releases.first(where: { $0.name == release }) { return r.tracks }
        return ArtistQueue.make(tracks, order: order, dedupe: false)
    }

    private func playAll() {
        let queue = ArtistQueue.make(tracks, order: order, dedupe: dedupe)
        if let first = queue.first { state.shuffleOn = false; state.play(first, from: queue) }
    }

    private func shuffle() {
        let queue = ArtistQueue.make(tracks, order: order, dedupe: dedupe).shuffled()
        if let first = queue.first { state.play(first, from: queue) }
    }

    private func card(name: String?, title: String, subtitle: String, cover: URL?) -> some View {
        let selected = release == name
        return Button { release = name } label: {
            VStack(alignment: .leading, spacing: 4) {
                ReleaseCover(url: name == nil ? nil : cover, symbol: name == nil ? "music.note.list" : "square.stack")
                    .frame(width: 86, height: 86)
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(theme.mutedText).lineLimit(1)
            }
            .frame(width: 86)
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? theme.accent.opacity(0.18) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? theme.accent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Capa de um lançamento (a da primeira faixa), ou um ícone.
private struct ReleaseCover: View {
    let url: URL?
    let symbol: String
    @StateObject private var covers = CoverLoader()
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let image = covers.image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(theme.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.artworkTint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onAppear { covers.load(url) }
    }
}
