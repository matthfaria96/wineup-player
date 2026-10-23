import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WineupLibrary

/// Editor de temas: tudo editável (inclusive os embutidos, com "Restaurar original"),
/// importar e exportar arquivos .wineuptheme.
struct ThemeEditorView: View {
    @ObservedObject private var store = ThemeStore.shared
    @AppStorage("themeID") private var activeID = "graphite"
    @State private var selectedID: String?
    @State private var error: String?
    @State private var confirmDelete = false

    private var selected: ThemeFile? { selectedID.flatMap { store.file($0) } }

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
            Group {
                if let theme = selected { editor(theme) } else { Text("Escolha um tema").foregroundStyle(.secondary) }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 560)
        .onAppear { selectedID = selectedID ?? activeID }
        .alert("Não foi possível", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .confirmationDialog("Apagar o tema “\(selected?.name ?? "")”?", isPresented: $confirmDelete) {
            Button("Apagar", role: .destructive) { deleteSelected() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: Lista

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                Section("Embutidos") {
                    ForEach(store.files.filter(\.isBuiltIn)) { row($0) }
                }
                let mine = store.files.filter { !$0.isBuiltIn }
                Section("Meus temas") {
                    if mine.isEmpty { Text("Nenhum ainda").foregroundStyle(.secondary).font(.caption) }
                    ForEach(mine) { row($0) }
                }
            }
            Divider()
            HStack(spacing: 4) {
                Button { run { selectedID = try store.duplicate(selected ?? .graphite, name: "Novo tema").id } } label: {
                    Image(systemName: "plus")
                }
                .help("Novo tema (a partir do selecionado)")
                Button { run { if let s = selected { selectedID = try store.duplicate(s).id } } } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Duplicar")
                .disabled(selected == nil)
                Button { confirmDelete = true } label: { Image(systemName: "minus") }
                    .help("Apagar tema")
                    .disabled(selected?.isBuiltIn ?? true)
                Spacer()
                Menu {
                    Button("Importar tema…") { importTheme() }
                    Button("Exportar tema…") { exportTheme() }.disabled(selected == nil)
                    Divider()
                    Button("Mostrar a pasta dos temas") {
                        try? FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(store.folder)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func row(_ file: ThemeFile) -> some View {
        HStack(spacing: 8) {
            Swatch(theme: Theme(file)).frame(width: 34, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).lineLimit(1)
                if file.id == activeID { Text("Em uso").font(.caption2).foregroundStyle(Color.accentColor) }
                else if store.isModifiedBuiltIn(file.id) { Text("Editado").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .tag(file.id)
    }

    // MARK: Editor

    private func editor(_ file: ThemeFile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Nome", text: binding(file, \.name)).textFieldStyle(.roundedBorder).font(.system(size: 15, weight: .semibold))
                        TextField("Autor", text: binding(file, \.author)).textFieldStyle(.roundedBorder)
                    }
                    Spacer(minLength: 20)
                    VStack(alignment: .trailing, spacing: 6) {
                        Button(file.id == activeID ? "Em uso" : "Usar este tema") { activeID = file.id }
                            .buttonStyle(.borderedProminent)
                            .disabled(file.id == activeID)
                        if store.isModifiedBuiltIn(file.id) {
                            Button("Restaurar original") { run { try store.delete(file.id) } }.controlSize(.small)
                        }
                    }
                }
                ThemePreview(theme: Theme(file))
                    .frame(height: 170)
                Text("Cores").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], alignment: .leading, spacing: 10) {
                    ForEach(ThemeFile.Token.allCases) { token in
                        ColorPicker(selection: colorBinding(file, token), supportsOpacity: true) {
                            Text(token.label).font(.system(size: 12))
                        }
                    }
                }
                Text("Os temas ficam em arquivos .wineuptheme (texto JSON) na pasta dos temas: dá para editar à mão, mandar para outra pessoa e importar. Editar um tema embutido cria a sua versão dele; “Restaurar original” volta ao padrão.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    private func binding(_ file: ThemeFile, _ key: WritableKeyPath<ThemeFile, String>) -> Binding<String> {
        Binding(get: { store.file(file.id)?[keyPath: key] ?? "" }, set: { value in
            guard var current = store.file(file.id) else { return }
            current[keyPath: key] = value
            run { try store.save(current) }
        })
    }

    private func colorBinding(_ file: ThemeFile, _ token: ThemeFile.Token) -> Binding<Color> {
        Binding(get: {
            Color(hexString: store.file(file.id)?.colors[token.rawValue] ?? "") ?? .gray
        }, set: { color in
            guard var current = store.file(file.id) else { return }
            current.colors[token.rawValue] = color.hexString
            run { try store.save(current) }
        })
    }

    // MARK: Arquivos

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ThemeStore.fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { run { selectedID = try store.importTheme(from: url).id } }
    }

    private func exportTheme() {
        guard let theme = selected else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(theme.name).\(ThemeStore.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { try store.export(theme, to: url) }
    }

    private func deleteSelected() {
        guard let theme = selected, !theme.isBuiltIn else { return }
        run {
            try store.delete(theme.id)
            if activeID == theme.id { activeID = "graphite" }
            selectedID = activeID
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { self.error = "O arquivo do tema não pôde ser lido ou gravado (\(error.localizedDescription))." }
    }
}

/// Amostra pequena das cores principais (lista de temas e menus).
struct Swatch: View {
    let theme: Theme
    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [theme.windowTop, theme.windowBottom], startPoint: .top, endPoint: .bottom)
            theme.panelFill
            theme.accent
            theme.text
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15)))
    }
}

/// Prévia ao vivo: janela, painel, lista com seleção e faixa tocando, letra e visor.
struct ThemePreview: View {
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            panel {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Músicas").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.text)
                    row("Abertura do Vinho", "Os Taninos", fill: theme.rowSelection, color: theme.text)
                    row("Safra Antiga", "Os Taninos", fill: .clear, color: theme.currentRow)
                    row("Rolha Solta", "Os Taninos", fill: .clear, color: theme.text)
                }
            }
            panel {
                VStack(alignment: .leading, spacing: 8) {
                    SevenSegmentText(text: "-03:44", digitHeight: 24)
                    Capsule().fill(theme.control.opacity(0.45)).frame(height: 3)
                        .overlay(alignment: .leading) { Capsule().fill(theme.accent).frame(width: 70, height: 3) }
                    HStack {
                        ForEach(["backward.fill", "play.fill", "forward.fill"], id: \.self) { s in
                            Image(systemName: s).font(.system(size: 11)).foregroundStyle(theme.text)
                                .frame(width: 30, height: 20)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.control.opacity(0.75)))
                        }
                    }
                }
            }
            panel {
                VStack(spacing: 6) {
                    Text("This is what you get").font(.system(size: 11)).foregroundStyle(theme.lyricsIdle.opacity(0.75))
                    Text("Karma police").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.lyricsActive)
                    Text("Arrest this man").font(.system(size: 11)).foregroundStyle(theme.lyricsIdle.opacity(0.75))
                    RoundedRectangle(cornerRadius: 4).fill(theme.artworkTint).frame(width: 40, height: 40)
                        .overlay(Image(systemName: "music.note").foregroundStyle(theme.mutedText))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.theme, theme)
        .padding(10)
        .background(LinearGradient(colors: [theme.windowTop, theme.windowBottom], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func panel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.panelFill))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.panelBorder))
    }

    private func row(_ title: String, _ artist: String, fill: Color, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            Text(artist).font(.system(size: 9)).foregroundStyle(theme.mutedText)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4).fill(fill))
    }
}
