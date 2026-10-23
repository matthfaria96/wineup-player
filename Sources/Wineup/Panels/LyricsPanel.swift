import SwiftUI

struct LyricsPanel: View {
    @ObservedObject var state: PlayerState
    @ObservedObject private var clock: PlaybackClock

    init(state: PlayerState) {
        self.state = state
        self.clock = state.clock
    }

    @Environment(\.theme) private var theme

    var body: some View {
        Panel(title: "Letras") {
            VStack(spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            if state.lyricLines.isEmpty {
                                Text(state.currentTrack == nil ? "Toque uma música para ver a letra" : "Sem letra para esta faixa")
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.mutedText)
                                    .padding(.top, 30)
                            }
                            ForEach(Array(state.lyricLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 19 * state.lyricsScale, weight: index == state.activeLyricIndex ? .semibold : .regular))
                                    .foregroundStyle(index == state.activeLyricIndex ? theme.lyricsActive : theme.lyricsIdle.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                    .onChange(of: state.activeLyricIndex) { _, index in
                        withAnimation { proxy.scrollTo(index, anchor: .center) }
                    }
                }
                HStack(spacing: 6) {
                    origin
                    Spacer(minLength: 4)
                    sizeButton(size: 10) { state.lyricsScale = max(state.lyricsScale - 0.1, 0.6) }
                    sizeButton(size: 14) { state.lyricsScale = min(state.lyricsScale + 0.1, 1.6) }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }

    /// Tipo e origem da letra: sincronizada/estática, do arquivo ou do LRCLIB (com opção de salvar).
    @ViewBuilder private var origin: some View {
        switch state.lyricsOrigin {
        case .local(let synced):
            kind(synced)
        case .online(let lyrics, _):
            kind(lyrics.isSynced)
            Text("LRCLIB").font(.system(size: 10)).foregroundStyle(theme.mutedText)
            Button("Salvar .lrc") { state.saveOnlineLyrics() }
                .buttonStyle(.borderless).font(.system(size: 10))
                .help("Gravar esta letra como .lrc ao lado da música")
        case .searching:
            ProgressView().controlSize(.mini)
        case .none:
            EmptyView()
        }
        Menu {
            Toggle("Buscar letras na internet (LRCLIB)", isOn: $state.lyricsOnline)
        } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Quando a música não tem letra, procurar no LRCLIB (envia título, artista, álbum e duração)")
    }

    private func kind(_ synced: Bool) -> some View {
        Label(synced ? "Sincronizada" : "Estática", systemImage: synced ? "clock.fill" : "text.alignleft")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(synced ? Color.green : Color.orange)
            .help(synced ? "Cada linha tem tempo: a letra acompanha a música" : "Sem marcas de tempo: não acompanha a música")
    }

    private func sizeButton(size: CGFloat, action: @escaping () -> Void) -> some View {
        ChromeButton(action: action) {
            Text("A").font(.system(size: size, weight: .semibold))
        }
        .frame(width: 34)
    }
}
