import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WineupLibrary

/// Editor de skins: tudo aberto. Cores, cada imagem (fundo, painéis, moldura, botões, puxador),
/// camadas animadas; novo/duplicar, importar/exportar .wineupskin, apagar, restaurar original.
struct SkinEditorView: View {
    @ObservedObject private var store = SkinStore.shared
    @ObservedObject private var history = SkinHistory.shared
    @AppStorage("themeID") private var activeID = SkinStore.defaultID
    @State private var selectedID: String?
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var tab = Tab.art
    @State private var showNew = false
    /// Duplicar pede o nome antes (evita cópia por clique sem querer).
    @State private var duplicateName: String?
    @State private var confirmRestore = false

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
        .onAppear {
            // Skin em uso pode ter sido apagado: cai no primeiro disponível.
            if store.skin(activeID) == nil { activeID = store.skins.first?.id ?? SkinStore.defaultID }
            selectedID = selectedID ?? activeID
        }
        .alert("Não foi possível", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .confirmationDialog("Apagar o skin “\(selected?.name ?? "")”?", isPresented: $confirmDelete) {
            Button("Apagar", role: .destructive) { deleteSelected() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("O skin e as imagens dele saem do Mac. Exporte antes se quiser guardar uma cópia.") }
        .confirmationDialog("Restaurar “\(selected?.name ?? "")” ao padrão?", isPresented: $confirmRestore) {
            Button("Restaurar padrão", role: .destructive) {
                if let s = selected { run { try store.restoreOfficial(s.id) }; history.reset(s.id) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Todos os seus ajustes neste skin oficial serão desfeitos.") }
        .alert("Duplicar skin", isPresented: Binding(get: { duplicateName != nil }, set: { if !$0 { duplicateName = nil } })) {
            TextField("Nome da cópia", text: Binding(get: { duplicateName ?? "" }, set: { duplicateName = $0 }))
            Button("Duplicar") {
                let name = (duplicateName ?? "").trimmingCharacters(in: .whitespaces)
                if let s = selected, !name.isEmpty { run { selectedID = try store.duplicate(s.id, name: name).id } }
                duplicateName = nil
            }
            Button("Cancelar", role: .cancel) { duplicateName = nil }
        } message: { Text("A cópia entra em Meus skins, onde pode ser editada e apagada à vontade.") }
    }

    // MARK: Lista

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                Section("Oficiais") {
                    ForEach(store.skins.filter { store.isOfficial($0.id) }) { sidebarRow($0) }
                }
                Section("Meus skins") {
                    let mine = store.skins.filter { !store.isOfficial($0.id) }
                    if mine.isEmpty {
                        Text("Crie com + ou duplique um oficial").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(mine) { sidebarRow($0) }
                }
            }
            Divider()
            HStack(spacing: 4) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .help("Novo skin a partir de uma imagem")
                Button { duplicateName = selected.map { "\($0.name) (cópia)" } } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Duplicar (pede o nome da cópia)")
                .disabled(selected == nil)
                Button { confirmDelete = true } label: { Image(systemName: "minus") }
                    .help(selected.map { store.isOfficial($0.id) } == true ? "Skins oficiais não podem ser apagados" : "Apagar skin")
                    .disabled(selected.map { store.isOfficial($0.id) } ?? true)
                Spacer()
                Menu {
                    Button("Importar skin…") { importSkin() }
                    Button("Exportar skin…") { exportSkin() }.disabled(selected == nil)
                    Divider()
                    Button("Mostrar a pasta dos meus skins") {
                        try? FileManager.default.createDirectory(at: store.userFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(store.userFolder)
                    }
                    Button("Mostrar a pasta deste skin") { if let s = selected { NSWorkspace.shared.open(s.folder) } }
                        .disabled(selected.map { store.isOfficial($0.id) && !store.isModifiedBuiltIn($0.id) } ?? true)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func sidebarRow(_ skin: Skin) -> some View {
        HStack(spacing: 8) {
            SkinThumb(skin: skin).frame(width: 46, height: 30).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(skin.name).lineLimit(1)
                HStack(spacing: 4) {
                    if skin.id == activeID { Text("Em uso").foregroundStyle(Color.accentColor) }
                    if store.isModifiedBuiltIn(skin.id) { Text("Ajustado").foregroundStyle(.secondary) }
                }
                .font(.caption2)
            }
        }
        .tag(skin.id)
    }

    /// Etiqueta de skin oficial (vem com o app).
    private var officialBadge: some View {
        Label("Oficial", systemImage: "checkmark.seal.fill")
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .foregroundStyle(Color.accentColor)
    }

    // MARK: Editor (organização no padrão dos Ajustes do macOS: seções agrupadas, rótulo à esquerda, controle à direita)

    private func editor(_ skin: Skin) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SkinThumb(skin: skin).frame(width: 52, height: 36).clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(skin.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if store.isOfficial(skin.id) { officialBadge }
                    }
                    Text(skin.manifest.author.isEmpty ? "Sem autor" : skin.manifest.author)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                ControlGroup {
                    Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .help("Desfazer (⌘Z)")
                        .keyboardShortcut("z", modifiers: .command)
                        .disabled(!history.canUndo(skin.id))
                    Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .help("Refazer (⇧⌘Z)")
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .disabled(!history.canRedo(skin.id))
                }
                .fixedSize()
                if store.isModifiedBuiltIn(skin.id) {
                    Button("Restaurar padrão") { confirmRestore = true }
                        .help("Desfaz os seus ajustes neste skin oficial")
                }
                Button(skin.id == activeID ? "Em uso" : "Usar este skin") { activeID = skin.id }
                    .buttonStyle(.borderedProminent)
                    .disabled(skin.id == activeID)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .padding(.bottom, 4)
            Form {
                if tab != .layers {
                    Section {
                        SkinPreview(skin: skin).frame(height: 230)
                            .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                    }
                }
                legibilitySection(skin)
                switch tab {
                case .art: artTab(skin)
                case .layers: layersTab(skin)
                case .colors: colorsTab(skin)
                case .about: aboutTab(skin)
                }
            }
            .formStyle(.grouped)
        }
    }

    /// Aviso quando o texto fica difícil de ler sobre algum painel, com correção automática.
    @ViewBuilder private func legibilitySection(_ skin: Skin) -> some View {
        let issues = SkinLegibility.issues(skin.manifest, folder: skin.folder)
        if !issues.isEmpty {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Texto difícil de ler").font(.system(size: 12, weight: .semibold))
                        Text(issues.map { Self.panelName($0.panel) }.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Ajustar automaticamente") { mutate(skin) { $0 = SkinLegibility.autoFix($0, folder: skin.folder) } }
                }
            }
        }
    }

    // MARK: Arte

    @ViewBuilder private func artTab(_ skin: Skin) -> some View {
        Section("Informações") {
            TextField("Nome", text: text(skin, \.name))
            TextField("Autor", text: text(skin, \.author))
        }
        Section {
            artRow(skin, "Fundo", file: skin.manifest.window.background?.image, dim: skin.manifest.window.background?.dim) { m, name, dim in
                var bg = m.window.background ?? SkinManifest.Fill(image: name ?? "")
                if let name { bg.image = name }
                if let dim { bg.dim = dim }
                m.window.background = bg
            }
            artRow(skin, "Arte do skin", file: skin.manifest.artwork, dim: nil) { m, name, _ in
                if let name { m.artwork = name }
            }
        } header: { Text("Janela") } footer: {
            Text("A arte do skin aparece no painel da capa (modo Arte do skin, ou quando a música não tem capa).")
        }
        Section {
            ForEach(["default", "player", "equalizer", "playlist", "artwork", "lyrics"], id: \.self) { key in
                let style = skin.manifest.panels[key]
                artRow(skin, Self.panelName(key).capitalized, file: style?.fill?.image, dim: style?.fill?.dim) { m, name, dim in
                    var st = m.panels[key] ?? m.panels["default"] ?? SkinManifest.PanelStyle()
                    var fill = st.fill ?? SkinManifest.Fill(image: name ?? "")
                    if let name { fill.image = name }
                    if let dim { fill.dim = dim }
                    st.fill = fill
                    m.panels[key] = st
                }
            }
        } header: { Text("Painéis") } footer: {
            Text("“Escurecer” cobre a imagem com preto para o texto continuar legível.")
        }
        Section("Controles") {
            artRow(skin, "Moldura", file: skin.manifest.panels["default"]?.frame?.image, dim: nil) { m, name, _ in
                guard let name else { return }
                for key in m.panels.keys {
                    var st = m.panels[key]!
                    st.frame = SkinManifest.NineSlice(image: name, slice: st.frame?.slice ?? 48, width: st.frame?.width ?? 12)
                    m.panels[key] = st
                }
            }
            artRow(skin, "Botão", file: skin.manifest.controls.button?.image, dim: nil) { m, name, _ in
                if let name { m.controls.button = SkinManifest.NineSlice(image: name, slice: m.controls.button?.slice ?? 14, width: m.controls.button?.width ?? 7) }
            }
            artRow(skin, "Botão ligado", file: skin.manifest.controls.buttonOn?.image, dim: nil) { m, name, _ in
                if let name { m.controls.buttonOn = SkinManifest.NineSlice(image: name, slice: m.controls.buttonOn?.slice ?? 14, width: m.controls.buttonOn?.width ?? 7) }
            }
            artRow(skin, "Campo de busca", file: skin.manifest.controls.field?.image, dim: nil) { m, name, _ in
                if let name { m.controls.field = SkinManifest.NineSlice(image: name, slice: m.controls.field?.slice ?? 14, width: m.controls.field?.width ?? 7) }
            }
            artRow(skin, "Puxador dos sliders", file: skin.manifest.controls.knob, dim: nil) { m, name, _ in
                if let name { m.controls.knob = name }
            }
            LabeledContent("Brilho do visor") {
                Slider(value: Binding(get: { skin.manifest.display.glow }, set: { v in mutate(skin) { $0.display.glow = v } }), in: 0...1)
                    .frame(width: 200)
            }
        }
    }

    /// Linha de imagem: miniatura e nome à esquerda; escurecer e trocar à direita.
    private func artRow(_ skin: Skin, _ label: String, file: String?, dim: Double?,
                        apply: @escaping (inout SkinManifest, String?, Double?) -> Void) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                if let dim {
                    Image(systemName: "sun.min").foregroundStyle(.secondary).help("Escurecer")
                    Slider(value: Binding(get: { dim }, set: { v in mutate(skin) { apply(&$0, nil, v) } }), in: 0...0.9)
                        .frame(width: 120)
                }
                Button("Trocar…") {
                    guard let url = Self.pickImage() else { return }
                    run {
                        let name = try store.addAsset(url, to: skin.id)
                        mutate(skin) { apply(&$0, name, nil) }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let f = file, let img = NSImage(contentsOf: skin.file(f)) { Image(nsImage: img).resizable().scaledToFill() }
                    else { Image(systemName: "photo").foregroundStyle(.secondary) }
                }
                .frame(width: 40, height: 28).clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                    Text(file ?? "Padrão do app").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Animação

    @ViewBuilder private func layersTab(_ skin: Skin) -> some View {
        SkinLayerStage(skin: skin, save: { m in commit(m) }, addImage: {
            guard let url = Self.pickImage() else { return nil }
            var name: String?
            run { name = try store.addAsset(url, to: skin.id) }
            return name
        })
    }

    // MARK: Cores

    @ViewBuilder private func colorsTab(_ skin: Skin) -> some View {
        let groups: [(String, [SkinManifest.ColorToken])] = [
            ("Janela e painéis", [.windowTop, .windowBottom, .panelFill, .panelBorder]),
            ("Texto", [.text, .mutedText]),
            ("Destaques e lista", [.accent, .rowSelection, .currentRow]),
            ("Botões e controles", [.buttonText, .buttonTextOn, .control, .display]),
            ("Letras e capa", [.lyricsActive, .lyricsIdle, .artworkTint]),
        ]
        ForEach(groups, id: \.0) { title, tokens in
            Section(title) {
                ForEach(tokens) { token in
                    ColorPicker(token.label, selection: Binding(get: {
                        Color(hexString: skin.manifest.colors[token.rawValue] ?? SkinManifest.fallbackColors[token.rawValue]!) ?? .gray
                    }, set: { color in mutate(skin) { $0.colors[token.rawValue] = color.hexString } }), supportsOpacity: true)
                }
            }
        }
    }

    // MARK: Créditos

    @ViewBuilder private func aboutTab(_ skin: Skin) -> some View {
        Section("Descrição") {
            TextField("Descrição", text: text(skin, \.description), axis: .vertical).lineLimit(2...5)
        }
        Section("Créditos") {
            if skin.manifest.credits.isEmpty { Text("Nenhum crédito").foregroundStyle(.secondary) }
            ForEach(Array(skin.manifest.credits.enumerated()), id: \.offset) { _, c in
                LabeledContent {
                    if let url = URL(string: c.source) { Link("Fonte", destination: url) }
                } label: {
                    Text(c.work)
                    Text("\(c.author) · \(c.license)")
                }
            }
        }
        Section {
            LabeledContent("Formato", value: "Pasta com skin.json, imagens e fontes")
            LabeledContent("Arquivo", value: ".wineupskin (ZIP)")
        } footer: {
            Text("Tudo pode ser editado à mão: use ⋯ › Mostrar a pasta deste skin.")
        }
    }

    // MARK: Ações

    private func text(_ skin: Skin, _ key: WritableKeyPath<SkinManifest, String>) -> Binding<String> {
        Binding(get: { store.skin(skin.id)?.manifest[keyPath: key] ?? "" }, set: { v in mutate(skin) { $0[keyPath: key] = v } })
    }

    private func mutate(_ skin: Skin, _ change: (inout SkinManifest) -> Void) {
        guard var m = store.skin(skin.id)?.manifest else { return }
        change(&m)
        commit(m)
    }

    /// Único caminho de gravação do editor: guarda o estado anterior para ⌘Z.
    private func commit(_ m: SkinManifest) {
        guard let before = store.skin(m.id)?.manifest, before != m else { return }
        history.record(before)
        run { try store.save(m) }
    }

    private func undo() {
        guard let s = selected, let m = history.undo(current: s.manifest) else { return }
        run { try store.save(m) }
    }

    private func redo() {
        guard let s = selected, let m = history.redo(current: s.manifest) else { return }
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
            guard !store.isOfficial(skin.id) else { return }
            try store.delete(skin.id)
            history.reset(skin.id)
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
