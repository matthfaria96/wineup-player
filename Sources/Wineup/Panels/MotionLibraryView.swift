import AVFoundation
import AppKit
import SwiftUI

/// Configuração dos Vídeos Personalizados, no estilo do seletor de papel de parede do macOS:
/// prévia grande do escolhido, grades de miniaturas vivas e a lista dos vídeos da categoria.
/// Oficiais não se apagam (só trocam de pasta); as categorias do usuário sim.
struct MotionLibraryView: View {
    @Binding var modeRaw: String
    @Binding var videoCategory: String
    @ObservedObject private var store = VideoCategoryStore.shared
    @AppStorage(MotionChoice.key) private var motion = ""
    @Environment(\.dismiss) private var dismiss
    @State private var naming = false
    @State private var newName = ""
    @State private var confirmDelete: VideoCategory?

    private static let scenes: [VisualMode] = [.aurora, .fjord, .city, .universe]
    private let grid = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)]

    private var selectedScene: VisualMode? {
        motion.hasPrefix("scene:") ? VisualMode(rawValue: String(motion.dropFirst(6))) : nil
    }
    private var selectedCategory: VideoCategory? {
        motion.hasPrefix("video:") ? store.category(String(motion.dropFirst(6))) : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    section("Animações", "Desenhadas pelo app, respiram com a música.") {
                        LazyVGrid(columns: grid, spacing: 14) {
                            ForEach(Self.scenes) { m in
                                Card(title: m.title, caption: "Oficial", selected: selectedScene == m) {
                                    VisualScene(mode: m, energy: { 0.25 }, seed: 7)
                                } action: { choose("scene:\(m.rawValue)") }
                            }
                        }
                    }
                    section("Vídeos", "Sem som, um clipe diferente a cada música.") {
                        LazyVGrid(columns: grid, spacing: 14) {
                            ForEach(store.categories) { c in categoryCard(c) }
                            addCard
                        }
                    }
                    if let c = selectedCategory { clipList(c) }
                }
                .padding(20)
            }
        }
        .frame(width: 720, height: 660)
        .alert("Nova categoria de vídeos", isPresented: $naming) {
            TextField("Nome (ex.: Viagens)", text: $newName)
            Button("Escolher pasta…") { createCategory() }
            Button("Cancelar", role: .cancel) { newName = "" }
        } message: { Text("Depois escolha a pasta com seus vídeos MP4 ou MOV.") }
        .confirmationDialog("Apagar a categoria “\(confirmDelete?.name ?? "")”?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Apagar", role: .destructive) {
                if let c = confirmDelete { store.remove(c.id); if motion == "video:\(c.id)" { motion = "" } }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Os vídeos na sua pasta não são apagados.") }
    }

    // MARK: Partes

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vídeos Personalizados").font(.title3.weight(.semibold))
                Text("Escolha o que aparece no lugar da capa.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Concluído") { dismiss() }.keyboardShortcut(.defaultAction).controlSize(.large)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    /// Prévia grande do que está escolhido (ou um convite, se nada foi escolhido).
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14).fill(.black)
            if let m = selectedScene {
                VisualScene(mode: m, energy: { 0.3 }, seed: 7)
            } else if let c = selectedCategory, !c.clips.isEmpty {
                VideoWall(clips: c.clips, trackKey: 0)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack").font(.system(size: 34, weight: .light))
                    Text(selectedCategory == nil ? "Escolha uma animação ou categoria abaixo" : "Esta categoria ainda não tem vídeos")
                        .font(.callout)
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let name = MotionChoice.label(motion) {
                Text(name).font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
    }

    private func section<Content: View>(_ title: String, _ caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Text(caption).font(.callout).foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func categoryCard(_ c: VideoCategory) -> some View {
        let n = c.clips.count
        return Card(title: c.name, caption: (c.builtIn ? "Oficial · " : "") + (n == 0 ? "Sem vídeos" : "\(n) vídeo\(n == 1 ? "" : "s")"),
                    selected: selectedCategory?.id == c.id) {
            if let first = c.clips.first { VideoThumbnail(url: first) }
            else { Image(systemName: c.symbol).font(.system(size: 26, weight: .light)).foregroundStyle(.white.opacity(0.6)) }
        } action: { choose("video:\(c.id)") }
        .contextMenu { folderActions(c) }
    }

    private var addCard: some View {
        Button { newName = ""; naming = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(.tertiary)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .overlay(Image(systemName: "plus").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary))
                Text("Nova categoria").font(.callout)
                Text("Com uma pasta sua").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Os vídeos da categoria escolhida, com miniatura e nome.
    private func clipList(_ c: VideoCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Vídeos em \(c.name)").font(.headline)
                Spacer()
                Menu("Pasta") { folderActions(c) }.menuStyle(.borderlessButton).fixedSize()
            }
            if c.clips.isEmpty {
                Text("Nenhum vídeo ainda. Acople uma pasta com arquivos MP4 ou MOV.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(c.clips.enumerated()), id: \.element) { i, url in
                        if i > 0 { Divider().padding(.leading, 106) }
                        HStack(spacing: 12) {
                            VideoThumbnail(url: url)
                                .frame(width: 84, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.clipTitle(url, category: c))
                                Text(url.deletingLastPathComponent().path.contains(".app/") ? "Incluído no app" : url.deletingLastPathComponent().lastPathComponent)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
            }
        }
    }

    @ViewBuilder private func folderActions(_ c: VideoCategory) -> some View {
        Button(c.folder == nil ? "Acoplar uma pasta de vídeos…" : "Trocar a pasta…") {
            if let f = VideoCategoriesView.pickFolder() { var d = c; d.folder = f.path; store.update(d) }
        }
        if let folder = c.folder {
            Button("Mostrar no Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: folder)) }
            Button("Remover a pasta acoplada") { var d = c; d.folder = nil; store.update(d) }
        }
        if !c.builtIn {
            Divider()
            Button("Apagar categoria…", role: .destructive) { confirmDelete = c }
        }
    }

    // MARK: Ações

    private func choose(_ id: String) {
        motion = id
        if id.hasPrefix("scene:") { modeRaw = String(id.dropFirst(6)) }
        else { videoCategory = String(id.dropFirst(6)); modeRaw = VisualMode.videos.rawValue }
    }

    private func createCategory() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        newName = ""
        guard !name.isEmpty else { return }
        let c = store.add(name: name, folder: VideoCategoriesView.pickFolder())
        choose("video:\(c.id)")
    }

    /// "natureza-floresta.mp4" → "Floresta"; arquivos do usuário só perdem a extensão.
    static func clipTitle(_ url: URL, category: VideoCategory) -> String {
        var base = url.deletingPathExtension().lastPathComponent
        if category.bundled.contains(url.lastPathComponent), let dash = base.firstIndex(of: "-") {
            base = String(base[base.index(after: dash)...])
        }
        let words = base.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

/// Cartão de miniatura com título e legenda; o escolhido ganha borda de destaque.
private struct Card<Preview: View>: View {
    let title: String
    let caption: String
    let selected: Bool
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color.black
                    preview()
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                        .padding(-4)
                )
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor)
                            .font(.system(size: 18)).padding(6)
                    }
                }
                Text(title).font(.callout).lineLimit(1)
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Primeiro quadro (a 1 s) de um vídeo, gerado uma vez e guardado em memória.
struct VideoThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        ZStack {
            Color.black
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { ProgressView().controlSize(.small) }
        }
        .clipped()
        .task(id: url) { image = await Self.load(url) }
    }

    static func load(_ url: URL) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 300)
        guard let cg = try? await gen.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image else { return nil }
        let img = NSImage(cgImage: cg, size: .zero)
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}
