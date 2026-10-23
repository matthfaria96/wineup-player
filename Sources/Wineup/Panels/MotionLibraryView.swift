import AVFoundation
import AppKit
import SwiftUI

/// Configuração dos Vídeos Personalizados, no estilo do seletor de papel de parede do macOS:
/// grades de miniaturas vivas e a lista dos vídeos da categoria.
/// As oficiais são fixas; o usuário só cria, edita e apaga as próprias categorias.
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
    private static let columns = 4
    private static let gap: CGFloat = 14
    /// Largura útil (720 − margens) dividida em 4 colunas fixas: assim o balão sabe onde apontar.
    private static let cellWidth: CGFloat = (680 - gap * CGFloat(columns - 1)) / CGFloat(columns)
    private let grid = Array(repeating: GridItem(.fixed(cellWidth), spacing: gap), count: columns)

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
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Animações", "Desenhadas pelo app, respiram com a música.") {
                        LazyVGrid(columns: grid, spacing: 14) {
                            ForEach(Self.scenes) { m in
                                Card(title: m.title, caption: "Animação", selected: selectedScene == m) {
                                    VisualScene(mode: m, energy: { 0.25 }, seed: 7)
                                } action: { choose("scene:\(m.rawValue)") }
                            }
                        }
                    }
                    section("Vídeos", "Sem som, um clipe diferente a cada música.") {
                        videoGrid
                    }
                }
                .padding(20)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: motion)
            }
            .onChange(of: motion) { _, new in
                guard new.hasPrefix("video:") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo("clips", anchor: .bottom) }
                }
            }
            }
        }
        .frame(width: 720, height: 680)
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
        return Card(title: c.name, caption: n == 0 ? "Sem vídeos" : "\(n) vídeo\(n == 1 ? "" : "s")",
                    selected: selectedCategory?.id == c.id) {
            if let first = c.clips.first { VideoThumbnail(url: first) }
            else { Image(systemName: c.symbol).font(.system(size: 26, weight: .light)).foregroundStyle(.white.opacity(0.6)) }
        } action: { choose("video:\(c.id)") }
        .contextMenu { if !c.builtIn { folderActions(c) } }
    }

    private var addCard: some View {
        Button { newName = ""; naming = true } label: {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.tertiary)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 22, weight: .light))
                        Text("Nova categoria").font(.callout)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(4)
        }
        .buttonStyle(.plain)
    }

    /// Grade de categorias em linhas; abaixo da linha do card escolhido abre um balão
    /// com a ponta apontando para ele, com os vídeos tocando em players pequenos.
    private var videoGrid: some View {
        let items: [VideoCategory?] = store.categories.map { Optional($0) } + [nil]
        let rows = stride(from: 0, to: items.count, by: Self.columns).map { Array(items[$0..<min($0 + Self.columns, items.count)]) }
        return VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        Group {
                            if let c = rows[r][i] { categoryCard(c) } else { addCard }
                        }
                        .frame(width: Self.cellWidth)
                    }
                }
                if let c = selectedCategory, let col = rows[r].firstIndex(where: { $0?.id == c.id }) {
                    clipBubble(c, arrowX: CGFloat(col) * (Self.cellWidth + Self.gap) + Self.cellWidth / 2)
                        .id("clips")
                        .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
        }
    }

    private func clipBubble(_ c: VideoCategory, arrowX: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Vídeos em \(c.name)").font(.subheadline.weight(.semibold))
                Spacer()
                if !c.builtIn {
                    Menu("Pasta") { folderActions(c) }.menuStyle(.borderlessButton).fixedSize()
                }
            }
            if c.clips.isEmpty {
                Text("Nenhum vídeo ainda. Acople uma pasta com arquivos MP4 ou MOV.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(c.clips, id: \.self) { url in
                            VStack(alignment: .leading, spacing: 5) {
                                ZStack {
                                    VideoThumbnail(url: url)
                                    VideoWall(clips: [url], trackKey: 0)
                                }
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08)))
                                Text(Self.clipTitle(url, category: c)).font(.caption).lineLimit(1)
                            }
                            .frame(width: 96)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 10 + Callout.arrow)
        .background {
            Callout(arrowX: arrowX).fill(.regularMaterial)
                .overlay(Callout(arrowX: arrowX).stroke(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
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
        Divider()
        Button("Apagar categoria…", role: .destructive) { confirmDelete = c }
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

/// Balão com ponta no topo (como os menus da barra do macOS), apontando para `arrowX`.
private struct Callout: Shape {
    static let arrow: CGFloat = 9
    var arrowX: CGFloat
    var animatableData: CGFloat { get { arrowX } set { arrowX = newValue } }

    func path(in rect: CGRect) -> Path {
        let a = Self.arrow, r: CGFloat = 12
        let body = CGRect(x: rect.minX, y: rect.minY + a, width: rect.width, height: rect.height - a)
        let x = min(max(arrowX, body.minX + r + a), body.maxX - r - a)
        var p = Path(roundedRect: body, cornerRadius: r, style: .continuous)
        var tip = Path()
        tip.move(to: CGPoint(x: x - a - 2, y: body.minY + 0.5))
        tip.addQuadCurve(to: CGPoint(x: x, y: rect.minY), control: CGPoint(x: x - 3, y: body.minY))
        tip.addQuadCurve(to: CGPoint(x: x + a + 2, y: body.minY + 0.5), control: CGPoint(x: x + 3, y: body.minY))
        tip.closeSubpath()
        p.addPath(tip)
        return p.union(tip)
    }
}

/// Cartão quadrado (como a capa): título por cima da imagem e uma etiqueta discreta.
private struct Card<Preview: View>: View {
    let title: String
    let caption: String
    let selected: Bool
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.black
                .aspectRatio(1, contentMode: .fit)
                .overlay { preview() }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(caption)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.white.opacity(0.2), in: Capsule())
                        Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                }
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
