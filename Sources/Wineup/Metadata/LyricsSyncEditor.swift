import SFBAudioEngine
import SwiftUI
import WineupCore
import WineupLibrary

/// Editor da letra: "Sincronia" (ouvir a música com a linha atual acesa e adiantar/atrasar a letra
/// inteira em passos de 0,25 s) e "Texto" (edição crua). As duas visões mexem no mesmo rascunho.
struct LyricsSyncEditor: View {
    @Binding var draft: String
    let fileURL: URL
    var onWillPlay: () -> Void = {}
    @StateObject private var preview = LyricsPreviewPlayer()
    @State private var mode: Mode = .sync
    /// Quanto a letra já foi deslocada nesta edição (só para mostrar).
    @State private var applied = 0.0

    enum Mode: Hashable { case sync, text }
    static let step = 0.25

    private var info: LyricsInfo { LyricsInfo(draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Editar", selection: $mode.animation(.snappy)) {
                Text("Sincronia").tag(Mode.sync)
                Text("Texto").tag(Mode.text)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch mode {
            case .sync: sync.transition(.opacity)
            case .text: text.transition(.opacity)
            }
        }
        .onDisappear { preview.stop() }
    }

    // MARK: Sincronia

    @ViewBuilder private var sync: some View {
        let info = info
        if info.isSynced {
            VStack(alignment: .leading, spacing: 8) {
                transport
                HStack(spacing: 6) {
                    Button { nudge(-Self.step) } label: { Label("0,25 s", systemImage: "backward.fill") }
                        .help("Adiantar a letra inteira 0,25 s (as linhas aparecem antes)")
                    Text(appliedText).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(applied == 0 ? Color.secondary : Color.accentColor)
                        .frame(minWidth: 64)
                        .contentTransition(.numericText(value: applied))
                    Button { nudge(Self.step) } label: { Label("0,25 s", systemImage: "forward.fill") }
                        .labelStyle(TrailingIconLabel())
                        .help("Atrasar a letra inteira 0,25 s (as linhas aparecem depois)")
                    Spacer(minLength: 0)
                    if applied != 0 {
                        Button { nudge(-applied) } label: { Image(systemName: "arrow.counterclockwise") }
                            .help("Voltar ao tempo original")
                    }
                }
                .controlSize(.small)
                lines(info)
                Text("Toque a música: a linha cantada fica acesa. Se ela acender antes da voz, atrase; se depois, adiante. Clique numa linha para pular até ela.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Esta letra não tem marcas de tempo", systemImage: "clock.badge.questionmark")
                    .font(.system(size: 12, weight: .medium))
                Text("Para sincronizar, busque uma letra sincronizada (lupa) ou escreva as marcas [mm:ss.xx] no início das linhas, na aba Texto.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
        }
    }

    private var appliedText: String {
        applied == 0 ? "Original" : String(format: "%@%.2f s", applied > 0 ? "+" : "−", abs(applied)).replacingOccurrences(of: ".", with: ",")
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button {
                if !preview.isLoaded { onWillPlay() }
                preview.toggle(fileURL)
            } label: {
                Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill").frame(width: 14)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(preview.isPlaying ? "Pausar" : "Tocar a música para conferir a letra")
            Text(LyricsInfo.clock(preview.time)).font(.system(size: 11).monospacedDigit()).frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { preview.time }, set: { preview.seek($0) }), in: 0...max(preview.duration, 1))
                .controlSize(.mini)
                .disabled(!preview.isLoaded)
        }
        .controlSize(.small)
    }

    private func lines(_ info: LyricsInfo) -> some View {
        let active = info.activeIndex(at: preview.time)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(info.lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(line.time.map(LyricsInfo.clock) ?? "").font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(line.id == active ? Color.accentColor : .secondary)
                                .frame(width: 44, alignment: .trailing)
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: 12, weight: line.id == active ? .semibold : .regular))
                                .foregroundStyle(line.id == active ? Color.primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2).padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 4).fill(line.id == active ? Color.accentColor.opacity(0.15) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard let t = line.time else { return }
                            if !preview.isLoaded { onWillPlay() }
                            preview.play(fileURL, from: t)
                        }
                        .id(line.id)
                    }
                }
                .padding(6)
            }
            .frame(minHeight: 240, maxHeight: 380)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            .onChange(of: active) { _, index in
                guard let index else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func nudge(_ seconds: Double) {
        draft = LyricsTiming.shift(draft, by: seconds)
        withAnimation(.snappy) { applied = ((applied + seconds) * 100).rounded() / 100 }
    }

    // MARK: Texto

    private var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $draft)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 300)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.5)))
            Text("Uma linha por verso. Com marcas como [01:23.45] no início das linhas, a letra fica sincronizada.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

/// Ícone depois do texto (o botão de atrasar aponta para a frente).
private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}

/// Player próprio da prévia (SFBAudioEngine): toca qualquer formato do app sem mexer na fila principal.
@MainActor
final class LyricsPreviewPlayer: ObservableObject {
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoaded = false

    private let player = AudioPlayer()
    private var timer: Timer?

    func toggle(_ url: URL) {
        if isPlaying { _ = player.pause(); isPlaying = false; return }
        if isLoaded { _ = player.resume(); isPlaying = true; return }
        play(url, from: 0)
    }

    func play(_ url: URL, from start: Double) {
        if !isLoaded {
            guard (try? player.play(url)) != nil else { return }
            isLoaded = true
            startTimer()
        } else if !isPlaying {
            _ = player.resume()
        }
        isPlaying = true
        if start > 0 { seek(start) }
    }

    func seek(_ t: Double) {
        guard isLoaded else { return }
        _ = player.seek(time: t)
        time = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
        isPlaying = false
        isLoaded = false
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.time = self.player.currentTime ?? self.time
                self.duration = self.player.totalTime ?? self.duration
                if self.player.isStopped { self.isPlaying = false; self.isLoaded = false }
            }
        }
    }
}
