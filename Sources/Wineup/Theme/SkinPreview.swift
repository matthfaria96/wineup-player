import SwiftUI
import WineupLibrary

/// Prévia fiel do skin com os componentes reais: topo (botões e busca), player, FX e lista.
struct SkinPreview: View {
    let skin: Skin
    @State private var volume = 0.7
    @State private var bands: [Double] = [3, -2, 4, 1, -3, 2, 5, -1]

    var body: some View {
        let theme = Theme(skin)
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Wineup Player").font(theme.titleFont(12, weight: .bold)).foregroundStyle(theme.text)
                Button {} label: { Image(systemName: "chevron.left").frame(width: 12) }.buttonStyle(SkinButtonStyle(compact: true))
                Button {} label: { Label("Metadados", systemImage: "tag").lineLimit(1).fixedSize() }.buttonStyle(SkinButtonStyle())
                Spacer()
                HStack { Image(systemName: "magnifyingglass"); Text("Buscar…").foregroundStyle(theme.mutedText); Spacer() }
                    .font(.system(size: 11)).padding(.horizontal, 8).frame(minWidth: 90, maxWidth: 160).frame(height: 22).skinField()
                Spacer()
                Button {} label: { Label("Completo", systemImage: "square.grid.2x2").lineLimit(1).fixedSize() }.buttonStyle(SkinButtonStyle(on: true))
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            HStack(spacing: 6) {
                Panel(title: "") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Músicas").font(theme.titleFont(18, weight: .bold)).foregroundStyle(theme.text)
                        row("Abertura do Vinho", "Os Taninos", current: false, selected: true, theme)
                        row("Safra Antiga", "Os Taninos", current: true, selected: false, theme)
                        row("Rolha Solta", "Os Taninos", current: false, selected: false, theme)
                    }
                    .padding(10)
                }
                .environment(\.panelKind, "playlist")
                VStack(spacing: 6) {
                    Panel(title: "Player") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Safra Antiga").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text)
                                Spacer()
                                SevenSegmentText(text: "-03:44", digitHeight: 18)
                            }
                            HStack(spacing: 4) {
                                ChromeButton(symbol: "backward.fill") {}
                                ChromeButton(symbol: "pause.fill", isOn: true) {}
                                ChromeButton(symbol: "forward.fill") {}
                            }
                            ChromeSlider(value: $volume, knobThickness: 12).frame(height: 16)
                        }
                        .padding(.horizontal, 10).padding(.bottom, 8)
                    }
                    .environment(\.panelKind, "player")
                    Panel(title: "FX") {
                        HStack(spacing: 0) {
                            ForEach(bands.indices, id: \.self) { i in
                                ChromeSlider(value: $bands[i], range: -12...12, axis: .vertical, knobLength: 9, knobThickness: 16)
                            }
                        }
                        .padding(.horizontal, 10).padding(.bottom, 8)
                    }
                    .environment(\.panelKind, "equalizer")
                }
                .frame(width: 230)
            }
        }
        .padding(8)
        .background {
            ZStack {
                LinearGradient(colors: [theme.windowTop, theme.windowBottom], startPoint: .top, endPoint: .bottom)
                if let art = theme.art {
                    SkinFillView(art: art, fill: art.manifest.window.background, layers: art.manifest.window.layers, energy: { 0.35 })
                }
            }
        }
        .environment(\.theme, theme)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
        .disabled(true)
    }

    private func row(_ title: String, _ artist: String, current: Bool, selected: Bool, _ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(current ? theme.currentRow : theme.text)
            Text(artist).font(.system(size: 9)).foregroundStyle(theme.mutedText)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? theme.rowSelection : .clear))
    }
}

/// Criar um skin a partir de uma imagem: escolher a imagem, nome e estilo de moldura/botões.
struct NewSkinFromImageView: View {
    let onCreated: (Skin) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: URL?
    @State private var name = ""
    @State private var style = SkinGenerator.Style.gold
    @State private var error: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Novo skin a partir de uma imagem").font(.headline)
            Text("Escolha uma foto, pintura ou arte. O Wineup monta o fundo, os painéis, as cores (tiradas da imagem, com o texto sempre legível) e a moldura e os botões no estilo escolhido. Depois dá para ajustar tudo no editor.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12))
                    if let image, let img = NSImage(contentsOf: image) {
                        Image(nsImage: img).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 28))
                            Text("Arraste uma imagem aqui").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 220, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                        DispatchQueue.main.async { if let url { pick(url) } }
                    }
                    return true
                }
                VStack(alignment: .leading, spacing: 10) {
                    Button("Escolher imagem…") { if let url = SkinEditorView.pickImage() { pick(url) } }
                    TextField("Nome do skin", text: $name).textFieldStyle(.roundedBorder)
                    Picker("Moldura e botões", selection: $style) {
                        ForEach(SkinGenerator.Style.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(working ? "Criando…" : "Criar skin") { create() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(image == nil || name.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
        }
        .padding(18)
        .frame(width: 560)
    }

    private func pick(_ url: URL) {
        image = url
        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ") }
    }

    private func create() {
        guard let image else { return }
        working = true
        let n = name.trimmingCharacters(in: .whitespaces), s = style
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try SkinStore.shared.createFromImage(image, name: n, style: s, author: NSFullUserName()) }
            DispatchQueue.main.async {
                working = false
                switch result {
                case .success(let skin): onCreated(skin); dismiss()
                case .failure: error = "Não foi possível ler essa imagem. Use JPG, PNG, HEIC ou similar."
                }
            }
        }
    }
}
