import SFBAudioEngine
import SwiftUI
import WineupLibrary

/// Uma letra para ver: a nova (vinda do LRCLIB), a do .lrc ou a embutida no arquivo.
struct LyricsSource: Identifiable, Hashable {
    let id: String
    let title: String
    let text: String
}

/// Toca a música e mostra a letra acompanhando: linha ativa em destaque, tempo de cada linha,
/// clique numa linha para pular até ela. Letra estática aparece inteira, com o aviso.
struct LyricsViewer: View {
    let fileURL: URL
    let songTitle: String
    let sources: [LyricsSource]
    let onWillPlay: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = LyricsPreviewPlayer()
    @State private var sourceID: String

    init(fileURL: URL, songTitle: String, sources: [LyricsSource], onWillPlay: @escaping () -> Void) {
        self.fileURL = fileURL
        self.songTitle = songTitle
        self.sources = sources
        self.onWillPlay = onWillPlay
        _sourceID = State(initialValue: sources.first?.id ?? "")
    }

    private var source: LyricsSource? { sources.first { $0.id == sourceID } }
    private var info: LyricsInfo { LyricsInfo(source?.text ?? "") }

    var body: some View {
        let info = info
        let active = info.activeIndex(at: preview.time)
        VStack(alignment: .leading, spacing: 10) {
            header(info)
            transport
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(info.lines) { line in
                            row(line, isActive: line.id == active, isPast: (active ?? -1) > line.id)
                                .id(line.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: active) { _, index in
                    guard let index else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) }
                }
            }
            HStack {
                Text(fileURL.deletingPathExtension().appendingPathExtension("lrc").lastPathComponent)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 620, height: 640)
        .onDisappear { preview.stop() }
    }

    private func header(_ info: LyricsInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(songTitle).font(.headline).lineLimit(1)
                Spacer()
                if sources.count > 1 {
                    Picker("", selection: $sourceID) {
                        ForEach(sources) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            HStack(spacing: 8) {
                LyricsKindBadge(info: info)
                Text(info.summary).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            let tags = [info.header["ar"], info.header["ti"], info.header["al"]].compactMap { $0 }
            if !tags.isEmpty {
                Text("Cabeçalho do .lrc: " + tags.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button {
                if !preview.isLoaded { onWillPlay() }
                preview.toggle(fileURL)
            } label: {
                Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill").frame(width: 18)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(preview.isPlaying ? "Pausar" : "Tocar a música para ver a letra acompanhar")
            Text(LyricsInfo.clock(preview.time)).monospacedDigit().frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { preview.time }, set: { preview.seek($0) }),
                   in: 0...max(preview.duration, 1))
                .disabled(!preview.isLoaded)
            Text(LyricsInfo.clock(preview.duration)).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
    }

    private func row(_ line: LyricsInfo.Line, isActive: Bool, isPast: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(line.time.map(LyricsInfo.clock) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 64, alignment: .trailing)
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(.system(size: isActive ? 17 : 14, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : isPast ? Color.secondary : Color.primary.opacity(0.8))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(isActive ? Color.accentColor.opacity(0.15) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            guard let t = line.time else { return }
            if !preview.isLoaded { onWillPlay() }
            preview.play(fileURL, from: t)
        }
        .help(line.time == nil ? "" : "Pular para \(LyricsInfo.clock(line.time!))")
    }
}

/// Selo "Sincronizada" (relógio) ou "Estática" (texto).
struct LyricsKindBadge: View {
    let info: LyricsInfo

    var body: some View {
        Label(info.label, systemImage: info.isSynced ? "clock.fill" : "text.alignleft")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill((info.isSynced ? Color.green : Color.orange).opacity(0.2)))
            .foregroundStyle(info.isSynced ? Color.green : Color.orange)
            .help(info.summary)
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
