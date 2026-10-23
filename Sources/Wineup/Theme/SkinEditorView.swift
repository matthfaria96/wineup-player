import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WineupLibrary

/// Editor de skins: tudo aberto. Cores, cada imagem (fundo, painéis, moldura, botões, puxador),
/// camadas animadas; novo/duplicar, importar/exportar .wineupskin, apagar, restaurar original.
struct SkinEditorView: View {
    @ObservedObject private var store = SkinStore.shared
    @AppStorage("themeID") private var activeID = SkinStore.defaultID
    @State private var selectedID: String?
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var tab = Tab.art
    @State private var showNew = false

    enum Tab: String, CaseIterable { case art = "Arte", layers = "Animação", colors = "Cores", about = "Créditos" }

    private var selected: Skin? { selectedID.flatMap { store.skin($0) } }

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
            Group {
                if let skin = selected { editor(skin) } else { Text("Escolha um skin").foregroundStyle(.secondary) }
            }
            .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 720)
        .sheet(isPresented: $showNew) { NewSkinFromImageView { skin in selectedID = skin.id; activeID = skin.id } }
        .onAppear { selectedID = selectedID ?? activeID }
        .alert("Não foi possível", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .confirmationDialog(confirmTitle, isPresented: $confirmDelete) {
            Button(selected?.builtIn == false && store.isBuiltInID(selected?.id ?? "") ? "Restaurar" : "Apagar", role: .destructive) { deleteSelected() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var confirmTitle: String {
        guard let s = selected else { return "" }
        return store.isBuiltInID(s.id) ? "Desfazer todas as suas mudanças em “\(s.name)”?" : "Apagar o skin “\(s.name)”?"
    }

    // MARK: Lista

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(store.skins) { skin in
                    HStack(spacing: 8) {
                        SkinThumb(skin: skin).frame(width: 46, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skin.name).lineLimit(1)
                            if skin.id == activeID { Text("Em uso").font(.caption2).foregroundStyle(Color.accentColor) }
                            else if store.isModifiedBuiltIn(skin.id) { Text("Editado").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    .tag(skin.id)
                }
            }
            Divider()
            HStack(spacing: 4) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .help("Novo skin a partir de uma imagem")
                Button { run { if let s = selected { selectedID = try store.duplicate(s.id, name: "\(s.name) (cópia)").id } } } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Duplicar (para criar um skin novo a partir deste)")
                .disabled(selected == nil)
                Button { confirmDelete = true } label: { Image(systemName: "minus") }
                    .help("Apagar skin (ou desfazer edições de um embutido)")
                    .disabled(selected.map { $0.builtIn } ?? true)
                Spacer()
                Menu {
                    Button("Importar skin…") { importSkin() }
                    Button("Exportar skin…") { exportSkin() }.disabled(selected == nil)
                    Divider()
                    Button("Mostrar a pasta deste skin") { if let s = selected { NSWorkspace.shared.open(s.folder) } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    // MARK: Editor

    private func editor(_ skin: Skin) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Nome", text: text(skin, \.name)).textFieldStyle(.roundedBorder).font(.system(size: 15, weight: .semibold))
                    TextField("Autor", text: text(skin, \.author)).textFieldStyle(.roundedBorder)
                }
                Spacer(minLength: 20)
                Button(skin.id == activeID ? "Em uso" : "Usar este skin") { activeID = skin.id }
                    .buttonStyle(.borderedProminent)
                    .disabled(skin.id == activeID)
            }
            .padding([.horizontal, .top], 18)
            SkinPreview(skin: skin)
                .frame(height: 250)
                .padding(.horizontal, 18)
                .padding(.top, 12)
            legibilityBanner(skin)
            Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().padding(18)
            ScrollView {
                Group {
                    switch tab {
                    case .art: artTab(skin)
                    case .layers: layersTab(skin)
                    case .colors: colorsTab(skin)
                    case .about: aboutTab(skin)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
        }
    }

    /// Aviso quando o texto fica difícil de ler sobre algum painel, com correção automática.
    @ViewBuilder private func legibilityBanner(_ skin: Skin) -> some View {
        let issues = SkinLegibility.issues(skin.manifest, folder: skin.folder)
        if !issues.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Texto difícil de ler em: " + issues.map { Self.panelName($0.panel) }.joined(separator: ", ") + ".")
                    .font(.system(size: 11))
                Spacer()
                Button("Ajustar automaticamente") {
                    mutate(skin) { $0 = SkinLegibility.autoFix($0, folder: skin.folder) }
                }
                .controlSize(.small)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
    }

    // Arte: cada imagem que o skin usa, com trocar e escurecer.
    private func artTab(_ skin: Skin) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            artRow(skin, "Fundo da janela", file: skin.manifest.window.background?.image, dim: skin.manifest.window.background?.dim) { m, name, dim in
                var bg = m.window.background ?? SkinManifest.Fill(image: name ?? "")
                if let name { bg.image = name }
                if let dim { bg.dim = dim }
                m.window.background = bg
            }
            ForEach(["default", "player", "equalizer", "playlist", "artwork", "lyrics"], id: \.self) { key in
                let style = skin.manifest.panels[key]
                artRow(skin, "Painel: \(Self.panelName(key))", file: style?.fill?.image, dim: style?.fill?.dim) { m, name, dim in
                    var st = m.panels[key] ?? m.panels["default"] ?? SkinManifest.PanelStyle()
                    var fill = st.fill ?? SkinManifest.Fill(image: name ?? "")
                    if let name { fill.image = name }
                    if let dim { fill.dim = dim }
                    st.fill = fill
                    m.panels[key] = st
                }
            }
            artRow(skin, "Moldura dos painéis (9 fatias)", file: skin.manifest.panels["default"]?.frame?.image, dim: nil) { m, name, _ in
                guard let name else { return }
                for key in m.panels.keys {
                    var st = m.panels[key]!
                    st.frame = SkinManifest.NineSlice(image: name, slice: st.frame?.slice ?? 40, width: st.frame?.width ?? 14)
                    m.panels[key] = st
                }
            }
            artRow(skin, "Botão", file: skin.manifest.controls.button?.image, dim: nil) { m, name, _ in
                if let name { m.controls.button = SkinManifest.NineSlice(image: name, slice: m.controls.button?.slice ?? 14, width: m.controls.button?.width ?? 7) }
            }
            artRow(skin, "Botão ligado", file: skin.manifest.controls.buttonOn?.image, dim: nil) { m, name, _ in
                if let name { m.controls.buttonOn = SkinManifest.NineSlice(image: name, slice: m.controls.buttonOn?.slice ?? 14, width: m.controls.buttonOn?.width ?? 7) }
            }
            artRow(skin, "Puxador dos sliders", file: skin.manifest.controls.knob, dim: nil) { m, name, _ in
                if let name { m.controls.knob = name }
            }
            HStack {
                Text("Brilho do visor").frame(width: 190, alignment: .leading)
                Slider(value: Binding(get: { skin.manifest.display.glow }, set: { v in mutate(skin) { $0.display.glow = v } }), in: 0...1)
            }
        }
    }

    private func artRow(_ skin: Skin, _ label: String, file: String?, dim: Double?,
                        apply: @escaping (inout SkinManifest, String?, Double?) -> Void) -> some View {
        HStack(spacing: 10) {
            Group {
                if let f = file, let img = NSImage(contentsOf: skin.file(f)) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 40).clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12, weight: .medium))
                Text(file ?? "padrão do app").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(width: 190, alignment: .leading)
            if let dim {
                Text("Escurecer").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { dim }, set: { v in mutate(skin) { apply(&$0, nil, v) } }), in: 0...0.9)
                    .frame(maxWidth: 160)
            }
            Spacer()
            Button("Trocar…") {
                guard let url = Self.pickImage() else { return }
                run {
                    let name = try store.addAsset(url, to: skin.id)
                    mutate(skin) { apply(&$0, name, nil) }
                }
            }
            .controlSize(.small)
        }
    }

    // Animação: cada camada, ligar/desligar, intensidade e velocidade.
    private func layersTab(_ skin: Skin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Camadas da janela").font(.headline)
            if skin.manifest.window.layers.isEmpty { Text("Nenhuma").foregroundStyle(.secondary) }
            ForEach(Array(skin.manifest.window.layers.enumerated()), id: \.offset) { i, layer in
                layerRow(skin, layer) { m, change in change(&m.window.layers[i]) }
            }
            ForEach(skin.manifest.panels.keys.sorted(), id: \.self) { key in
                let layers = skin.manifest.panels[key]?.layers ?? []
                if !layers.isEmpty {
                    Text("Painel: \(Self.panelName(key))").font(.headline).padding(.top, 6)
                    ForEach(Array(layers.enumerated()), id: \.offset) { i, layer in
                        layerRow(skin, layer) { m, change in change(&m.panels[key]!.layers[i]) }
                    }
                }
            }
            Text("Cada camada reage à música (brilha e acelera com o volume) quando “Reage” está ligado. Pontos, cores e novas camadas ficam no skin.json, na pasta do skin.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func layerRow(_ skin: Skin, _ layer: SkinManifest.Layer,
                          update: @escaping (inout SkinManifest, (inout SkinManifest.Layer) -> Void) -> Void) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { layer.enabled }, set: { v in mutate(skin) { update(&$0) { $0.enabled = v } } })).labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name?.capitalized ?? Self.kindName(layer.kind)).font(.system(size: 12, weight: .medium))
                Text(Self.kindName(layer.kind)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(width: 130, alignment: .leading)
            Text("Força").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { layer.intensity }, set: { v in mutate(skin) { update(&$0) { $0.intensity = v } } }), in: 0...1)
            Text("Velocidade").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { layer.speed }, set: { v in mutate(skin) { update(&$0) { $0.speed = v } } }), in: 0...3)
            Toggle("Reage", isOn: Binding(get: { layer.react }, set: { v in mutate(skin) { update(&$0) { $0.react = v } } }))
                .toggleStyle(.checkbox)
        }
        .opacity(layer.enabled ? 1 : 0.5)
    }

    private func colorsTab(_ skin: Skin) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], alignment: .leading, spacing: 10) {
            ForEach(SkinManifest.ColorToken.allCases) { token in
                ColorPicker(selection: Binding(get: {
                    Color(hexString: skin.manifest.colors[token.rawValue] ?? SkinManifest.fallbackColors[token.rawValue]!) ?? .gray
                }, set: { color in mutate(skin) { $0.colors[token.rawValue] = color.hexString } }), supportsOpacity: true) {
                    Text(token.label).font(.system(size: 12))
                }
            }
        }
    }

    private func aboutTab(_ skin: Skin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !skin.manifest.description.isEmpty { Text(skin.manifest.description).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(skin.manifest.credits.enumerated()), id: \.offset) { _, c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.work).font(.system(size: 12, weight: .semibold))
                    Text("\(c.author) · \(c.license)").font(.system(size: 11)).foregroundStyle(.secondary)
                    if let url = URL(string: c.source) { Link(c.source, destination: url).font(.system(size: 10)) }
                }
            }
            Text("Formato: uma pasta com skin.json, imagens e fontes; exportado como .wineupskin (ZIP). Tudo é editável à mão.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Ações

    private func text(_ skin: Skin, _ key: WritableKeyPath<SkinManifest, String>) -> Binding<String> {
        Binding(get: { store.skin(skin.id)?.manifest[keyPath: key] ?? "" }, set: { v in mutate(skin) { $0[keyPath: key] = v } })
    }

    private func mutate(_ skin: Skin, _ change: (inout SkinManifest) -> Void) {
        guard var m = store.skin(skin.id)?.manifest else { return }
        change(&m)
        run { try store.save(m) }
    }

    private func importSkin() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: SkinStore.fileExtension) ?? .zip, .zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { selectedID = try store.importSkin(from: url).id }
    }

    private func exportSkin() {
        guard let skin = selected else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(skin.name).\(SkinStore.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { try store.export(skin.id, to: url) }
    }

    private func deleteSelected() {
        guard let skin = selected else { return }
        run {
            try store.delete(skin.id)
            if store.skin(skin.id) == nil {
                if activeID == skin.id { activeID = SkinStore.defaultID }
                selectedID = activeID
            }
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { self.error = "O skin não pôde ser lido ou gravado (\(error.localizedDescription))." }
    }

    static func pickImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .tiff]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func panelName(_ key: String) -> String {
        ["default": "todos (padrão)", "player": "Player", "equalizer": "FX", "playlist": "Lista",
         "artwork": "Capa", "lyrics": "Letras"][key] ?? key
    }

    static func kindName(_ k: SkinManifest.Layer.Kind) -> String {
        switch k {
        case .stars: "Estrelas cintilando"
        case .swirl: "Redemoinhos girando"
        case .glow: "Halo que respira"
        case .flow: "Pinceladas de vento"
        case .image: "Imagem animada"
        }
    }
}

/// Miniatura viva de um skin: o fundo da janela com as camadas animadas e um painel de amostra.
struct SkinThumb: View {
    let skin: Skin

    var body: some View {
        let theme = Theme(skin)
        ZStack {
            LinearGradient(colors: [theme.windowTop, theme.windowBottom], startPoint: .top, endPoint: .bottom)
            if let art = theme.art {
                SkinFillView(art: art, fill: art.manifest.window.background, layers: art.manifest.window.layers, energy: { 0.3 })
            }
        }
        .clipped()
    }
}
