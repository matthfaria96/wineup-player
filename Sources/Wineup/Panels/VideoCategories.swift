import AVFoundation
import AppKit
import Foundation
import SwiftUI

/// Categoria de vídeos para o painel visual: as embutidas vêm com clipes dentro do app
/// (domínio público / Creative Commons) e podem ser desligadas; as do usuário apontam
/// para uma pasta e podem ser editadas e apagadas. Qualquer categoria aceita uma pasta extra.
struct VideoCategory: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var symbol: String
    var builtIn: Bool
    var enabled: Bool = true
    /// Pasta do usuário com vídeos (MP4/MOV) somados aos clipes embutidos.
    var folder: String?
    /// Clipes embutidos (nomes de arquivo em Resources/Videos/<id>/).
    var bundled: [String] = []

    static let builtIns: [VideoCategory] = [
        VideoCategory(id: "universo", name: String(localized: "Galáxia"), symbol: "sparkle", builtIn: true,
                      bundled: ["universo-buracos-negros.mp4", "universo-colisao.mp4"]),
        VideoCategory(id: "cinema", name: String(localized: "Séries e filmes"), symbol: "film", builtIn: true,
                      bundled: ["cinema-hooligan.mp4", "cinema-melies.mp4"]),
        VideoCategory(id: "cidades", name: String(localized: "Cidades"), symbol: "building.2", builtIn: true,
                      bundled: []),
        VideoCategory(id: "natureza", name: String(localized: "Natureza"), symbol: "leaf", builtIn: true,
                      bundled: ["natureza-aurora.mp4", "natureza-floresta.mp4", "natureza-praia.mp4"]),
        VideoCategory(id: "animacao", name: String(localized: "Anime"), symbol: "sparkles.tv", builtIn: true,
                      bundled: ["animacao-namakura.mp4"]),
    ]

    /// Nomes antigos das embutidas: não contam como renomeação do usuário.
    static let oldNames: Set<String> = ["Animação clássica", "Cinema clássico", "Universo"]
    /// Nomes originais (em português) das embutidas: salvos assim, seguem o idioma do app.
    static let sourceNames: Set<String> = ["Galáxia", "Séries e filmes", "Cidades", "Natureza", "Anime"]

    /// Clipes prontos para tocar: os embutidos que existem no app + os da pasta do usuário.
    var clips: [URL] {
        var out: [URL] = []
        if let base = Bundle.main.resourceURL?.appendingPathComponent("Videos/\(id)") {
            out += bundled.map { base.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        if let folder, !folder.isEmpty { out += Self.videos(in: URL(fileURLWithPath: folder)) }
        return out
    }

    static func videos(in folder: URL) -> [URL] {
        let exts: Set<String> = ["mp4", "m4v", "mov"]
        let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return (e?.allObjects as? [URL] ?? []).filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
    }
}

/// Guarda as categorias (ligadas/desligadas, pastas, as do usuário) em JSON no Application Support.
final class VideoCategoryStore: ObservableObject {
    static let shared = VideoCategoryStore()
    static let selectedKey = "artwork.videoCategory"

    @Published private(set) var categories: [VideoCategory] = []
    private let url: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Wineup", isDirectory: true)) {
        url = directory.appendingPathComponent("video-categories.json")
        load()
    }

    var enabled: [VideoCategory] { categories.filter(\.enabled) }

    func category(_ id: String) -> VideoCategory? { categories.first { $0.id == id } }

    private func load() {
        let saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([VideoCategory].self, from: $0) } ?? []
        let byID = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Embutidas: lista de clipes sempre a do app; o que o usuário mexeu (ligada, pasta, nome) vem do salvo.
        let builtIns = VideoCategory.builtIns.map { b -> VideoCategory in
            guard let s = byID[b.id] else { return b }
            var c = b; c.enabled = s.enabled; c.folder = s.folder
            if !VideoCategory.oldNames.contains(s.name) && !VideoCategory.sourceNames.contains(s.name) { c.name = s.name }
            return c
        }
        categories = builtIns + saved.filter { !$0.builtIn }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(categories).write(to: url, options: .atomic)
    }

    func update(_ category: VideoCategory) {
        guard let i = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[i] = category
        save()
    }

    @discardableResult
    func add(name: String, folder: URL?) -> VideoCategory {
        var id = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) }
        if id.isEmpty { id = "categoria" }
        var unique = id, n = 2
        while categories.contains(where: { $0.id == unique }) { unique = "\(id)-\(n)"; n += 1 }
        let c = VideoCategory(id: unique, name: name, symbol: "folder", builtIn: false, folder: folder?.path)
        categories.append(c)
        save()
        return c
    }

    /// Só as do usuário saem de vez; as embutidas apenas desligam.
    func remove(_ id: String) {
        guard let c = category(id) else { return }
        if c.builtIn { var d = c; d.enabled = false; update(d) } else { categories.removeAll { $0.id == id }; save() }
    }

    func restoreBuiltIn(_ id: String) {
        guard let b = VideoCategory.builtIns.first(where: { $0.id == id }) else { return }
        update(b)
    }
}

/// Toca os clipes de uma categoria, sem som, um atrás do outro; a música nova sorteia outro clipe.
struct VideoWall: NSViewRepresentable {
    let clips: [URL]
    let trackKey: Int
    /// Cantos arredondados no próprio layer (o recorte do SwiftUI não alcança a camada de vídeo).
    var cornerRadius: CGFloat = 0

    final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var lastKey: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: context.coordinator.player)
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        view.layer = layer
        context.coordinator.player.isMuted = true
        context.coordinator.player.preventsDisplaySleepDuringVideoPlayback = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator
        let key = "\(trackKey)|\(clips.map(\.path).joined())"
        guard c.lastKey != key else { return }
        c.lastKey = key
        guard !clips.isEmpty else { c.looper = nil; c.player.removeAllItems(); return }
        // Começa num clipe sorteado pela música e segue pelos outros em loop.
        let start = abs(trackKey) % clips.count
        let ordered = Array(clips[start...] + clips[..<start])
        c.looper = nil
        c.player.removeAllItems()
        if ordered.count == 1 {
            c.looper = AVPlayerLooper(player: c.player, templateItem: AVPlayerItem(url: ordered[0]))
        } else {
            for u in ordered { c.player.insert(AVPlayerItem(url: u), after: nil) }
            c.player.actionAtItemEnd = .advance
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak player = c.player] note in
                // Acabou a fila: recomeça do primeiro.
                guard let player, player.items().count <= 1, (note.object as? AVPlayerItem) == player.currentItem else { return }
                for u in ordered { player.insert(AVPlayerItem(url: u), after: nil) }
            }
        }
        c.player.play()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.looper = nil
    }
}

/// Tela de configuração das categorias: ligar/desligar, pasta extra, criar, renomear, apagar.
struct VideoCategoriesView: View {
    @ObservedObject private var store = VideoCategoryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renaming: VideoCategory?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categorias de vídeo").font(.headline)
            Text("As categorias embutidas já vêm com clipes (domínio público e Creative Commons) e podem ser desligadas. Crie as suas apontando para uma pasta com vídeos MP4 ou MOV; em qualquer categoria dá para acoplar uma pasta sua.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                Section("Embutidas") { ForEach(store.categories.filter(\.builtIn)) { row($0) } }
                Section("Minhas categorias") {
                    let mine = store.categories.filter { !$0.builtIn }
                    if mine.isEmpty { Text("Nenhuma ainda").font(.caption).foregroundStyle(.secondary) }
                    ForEach(mine) { row($0) }
                }
            }
            HStack {
                TextField("Nome da nova categoria (ex.: Anime, Filmes, Viagens)", text: $newName).textFieldStyle(.roundedBorder)
                Button("Criar e escolher pasta…") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    store.add(name: name, folder: Self.pickFolder())
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Text("Créditos dos clipes embutidos: Avisos de terceiros (menu Sobre).").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 620, height: 520)
        .alert("Renomear categoria", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nome", text: $renameText)
            Button("Salvar") { if var c = renaming { c.name = renameText; store.update(c) }; renaming = nil }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
    }

    private func row(_ c: VideoCategory) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { c.enabled }, set: { var d = c; d.enabled = $0; store.update(d) })).labelsHidden()
                .help(c.enabled ? "Ligada: aparece no menu do visual" : "Desligada")
            Image(systemName: c.symbol).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name).font(.system(size: 12, weight: .medium))
                Text(detail(c)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                Button(c.folder == nil ? "Acoplar uma pasta de vídeos…" : "Trocar a pasta…") {
                    if let f = Self.pickFolder() { var d = c; d.folder = f.path; store.update(d) }
                }
                if c.folder != nil { Button("Remover a pasta acoplada") { var d = c; d.folder = nil; store.update(d) } }
                Button("Renomear…") { renaming = c; renameText = c.name }
                Divider()
                if c.builtIn {
                    Button("Restaurar original") { store.restoreBuiltIn(c.id) }
                } else {
                    Button("Apagar categoria", role: .destructive) { store.remove(c.id) }
                }
            } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.vertical, 2)
        .opacity(c.enabled ? 1 : 0.55)
    }

    private func detail(_ c: VideoCategory) -> String {
        let n = c.clips.count
        var parts = [String(localized: "Clipes: \(n)")]
        if let f = c.folder { parts.append(String(localized: "pasta: \(NavPlaces.displayPath(URL(fileURLWithPath: f)))")) }
        if c.builtIn && n == 0 { parts.append(String(localized: "clipes embutidos ausentes nesta cópia do app")) }
        return parts.joined(separator: " · ")
    }

    static func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Escolha a pasta com os vídeos (MP4 ou MOV)")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
