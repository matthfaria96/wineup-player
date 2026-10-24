import AppKit
import SwiftUI

struct LyricsPanel: View {
    @ObservedObject var state: PlayerState
    /// Só a troca de linha redesenha a letra (não cada passo do relógio).
    @ObservedObject private var position: LyricsPosition

    init(state: PlayerState) {
        self.state = state
        position = state.lyricsPosition
    }

    @Environment(\.theme) private var theme

    var body: some View {
        // Uma conta por desenho (antes era uma por linha da letra).
        let activeIndex = position.index
        Panel(title: "Letras") {
            VStack(spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 18) {
                            if state.lyricLines.isEmpty {
                                Text(state.currentTrack == nil ? "Toque uma música para ver a letra" : "Letra indisponível")
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.mutedText)
                                    .padding(.top, 30)
                            }
                            if state.lyricsOrigin == .askConsent {
                                VStack(spacing: 10) {
                                    Text("Buscar letras online?").font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(theme.text)
                                    Text("Esta faixa não tem letra salva. " + OnlineConsent.whatIsSent)
                                        .font(.system(size: 11)).foregroundStyle(theme.mutedText)
                                        .multilineTextAlignment(.center)
                                    HStack {
                                        Button("Agora não") { state.answerLyricsConsent(false) }
                                            .buttonStyle(SkinButtonStyle())
                                        Button("Permitir") { state.answerLyricsConsent(true) }
                                            .buttonStyle(SkinButtonStyle(on: true))
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                            } else if isStatusMessage {
                                // "Título\nexplicação": título discreto e a explicação menor.
                                let parts = (state.lyricLines.first ?? "").components(separatedBy: "\n")
                                VStack(spacing: 6) {
                                    if state.lyricsOrigin == .searching { ProgressView().controlSize(.small) }
                                    Text(parts.first ?? "")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(theme.mutedText)
                                    if parts.count > 1 {
                                        Text(parts.dropFirst().joined(separator: " "))
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.mutedText.opacity(0.8))
                                    }
                                }
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.top, 30)
                            } else {
                            ForEach(Array(state.lyricLines.enumerated()), id: \.offset) { index, line in
                                let active = index == activeIndex
                                // Linha longa encolhe até 65% antes de quebrar; quando quebra, quebra entre palavras
                                // e fica centralizada como um bloco (sem palavras soltas em cada linha).
                                Text(line.isEmpty ? "♪" : line)
                                    .font(.system(size: (active ? 28 : 22) * state.lyricsScale,
                                                  weight: active ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(active ? theme.lyricsActive : theme.lyricsIdle.opacity(0.75))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.65)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 14)
                                    .scaleEffect(active ? 1 : 0.97)
                                    .animation(.easeOut(duration: 0.2), value: active)
                                    .id(index)
                            }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                    .onChange(of: activeIndex) { _, index in
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

    /// "Procurando…" / "Sem letra…" não são letra: aparecem pequenos e discretos.
    private var isStatusMessage: Bool {
        switch state.lyricsOrigin {
        case .none, .searching, .askConsent: true
        default: false
        }
    }

    /// Rodapé enxuto: só um selo pequeno (tipo da letra) e o menu "⋯" com estado, exportação e opções.
    @ViewBuilder private var origin: some View {
        switch state.lyricsOrigin {
        case .local(let synced): kind(synced)
        case .online(let lyrics, _): kind(lyrics.isSynced)
        default: EmptyView()
        }
        Menu {
            Section(statusLine) {
                switch state.lyricsOrigin {
                case .online:
                    Button { state.saveOnlineLyrics() } label: { Label("Salvar como .lrc ao lado da música", systemImage: "square.and.arrow.down") }
                case .local:
                    if let url = state.currentTrack?.url {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([url.deletingPathExtension().appendingPathExtension("lrc")]) } label: {
                            Label("Mostrar o .lrc no Finder", systemImage: "folder")
                        }
                    }
                default: EmptyView()
                }
            }
            Divider()
            Toggle("Buscar letras online quando a faixa não tiver", isOn: $state.lyricsOnline)
        } label: { Image(systemName: "ellipsis") }
            .skinMenuChrome(compact: true)
            .hint("Opções da letra", "Tamanho do texto, buscar letra online e outras opções do painel de letra.")
    }

    private var statusLine: String {
        switch state.lyricsOrigin {
        case .local(let synced): synced ? "Letra sincronizada, do arquivo" : "Letra estática, do arquivo"
        case .online(let l, _): (l.isSynced ? "Letra sincronizada" : "Letra estática") + ", encontrada online (não salva)"
        case .searching: "Procurando a letra…"
        case .askConsent: "Aguardando permissão para buscar online"
        case .none: "Sem letra"
        }
    }

    /// Selo só com ícone: relógio verde (sincronizada) ou texto laranja (estática); o nome vai na dica.
    private func kind(_ synced: Bool) -> some View {
        Image(systemName: synced ? "clock.fill" : "text.alignleft")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(synced ? Color.green : Color.orange)
            .help(synced ? "Sincronizada: cada linha tem tempo e acompanha a música" : "Estática: sem marcas de tempo, não acompanha a música")
            .accessibilityLabel(synced ? "Letra sincronizada" : "Letra estática")
    }

    private func sizeButton(size: CGFloat, action: @escaping () -> Void) -> some View {
        ChromeButton(action: action) {
            Text("A").font(.system(size: size, weight: .semibold))
        }
        .frame(width: 34)
    }
}
