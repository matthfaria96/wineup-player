import AppKit
import SwiftUI
import WineupLibrary

/// Palco das camadas animadas da janela: o fundo do skin com as animações rodando; clicar coloca
/// um ponto na camada escolhida, arrastar move, e a lista ao lado liga, ajusta, colore e apaga.
struct SkinLayerStage: View {
    let skin: Skin
    let save: (SkinManifest) -> Void
    let addImage: () -> String?

    @State private var selected = 0
    @State private var selectedPoint: Int?
    /// Pontos em edição durante o arrasto (grava ao soltar, sem reescrever o arquivo a cada movimento).
    @State private var draft: [SkinManifest.Point]?

    private var layers: [SkinManifest.Layer] { skin.manifest.window.layers }
    private var layer: SkinManifest.Layer? { layers.indices.contains(selected) ? layers[selected] : nil }
    private var usesPoints: Bool { layer.map { $0.kind != .flow } ?? false }

    /// Seções do formulário: palco, lista de camadas e os ajustes da camada escolhida.
    var body: some View {
        Section {
            stage.listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } footer: {
            Text(hint)
        }
        Section {
            if layers.isEmpty { Text("Nenhuma camada").foregroundStyle(.secondary) }
            ForEach(Array(layers.enumerated()), id: \.offset) { i, l in listRow(i, l) }
        } header: {
            HStack {
                Text("Camadas")
                Spacer()
                Menu {
                    Button { add(.stars) } label: { Label("Estrelas cintilando", systemImage: "sparkles") }
                    Button { add(.glow) } label: { Label("Halo que respira", systemImage: "sun.max") }
                    Button { add(.swirl) } label: { Label("Redemoinho girando", systemImage: "hurricane") }
                    Button { add(.flow) } label: { Label("Vento de pinceladas", systemImage: "wind") }
                    Divider()
                    Button { add(.image) } label: { Label("Imagem animada…", systemImage: "photo") }
                } label: { Label("Adicionar", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
        }
        if let l = layer { detail(l) }
    }

    /// Linha da lista: ícone do tipo, nome e resumo; marca a escolhida; liga/desliga à direita.
    private func listRow(_ i: Int, _ l: SkinManifest.Layer) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(l.kind))
                .frame(width: 24, height: 24)
                .foregroundStyle(i == selected ? Color.white : Color.accentColor)
                .background(RoundedRectangle(cornerRadius: 6).fill(i == selected ? Color.accentColor : Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(l.name?.capitalized ?? SkinEditorView.kindName(l.kind))
                Text(l.kind == .flow ? SkinEditorView.kindName(l.kind) : "\(SkinEditorView.kindName(l.kind)) · \(l.points.count) ponto(s)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: bind(i, \.enabled)).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .contentShape(Rectangle())
        .onTapGesture { selected = i; selectedPoint = nil }
    }

    /// Ajustes da camada escolhida, um por linha (rótulo à esquerda, controle à direita).
    @ViewBuilder private func detail(_ l: SkinManifest.Layer) -> some View {
        let i = selected
        Section(l.name?.capitalized ?? SkinEditorView.kindName(l.kind)) {
            TextField("Nome", text: Binding(get: { l.name ?? "" }, set: { v in update(i) { $0.name = v.isEmpty ? nil : v } }))
            if l.kind == .image {
                Picker("Movimento", selection: Binding(get: { l.motion ?? "float" }, set: { m in update(i) { $0.motion = m } })) {
                    Text("Flutua").tag("float"); Text("Gira").tag("spin"); Text("Pulsa").tag("pulse"); Text("Parada").tag("none")
                }
            } else {
                ColorPicker("Cor", selection: Binding(get: { Color(hexString: l.color ?? l.colors.first ?? "#FFFFFF") ?? .white },
                                                     set: { c in update(i) { $0.color = c.hexString; $0.colors = [] } }), supportsOpacity: false)
            }
            LabeledContent("Força") { Slider(value: bind(i, \.intensity), in: 0...1).frame(width: 220) }
            LabeledContent("Velocidade") { Slider(value: bind(i, \.speed), in: 0...3).frame(width: 220) }
            Toggle("Reage à música", isOn: bind(i, \.react))
            if l.kind != .flow {
                if let p = selectedPoint, l.points.indices.contains(p) {
                    LabeledContent("Tamanho do ponto") {
                        Slider(value: Binding(get: { l.points[p].r }, set: { v in update(i) { $0.points[p].r = v } }), in: 0.003...0.3)
                            .frame(width: 220)
                    }
                } else {
                    LabeledContent("Tamanho do ponto") { Text("Escolha um ponto no palco").foregroundStyle(.secondary) }
                }
            }
            HStack {
                Spacer()
                Button("Apagar camada", role: .destructive) { removeLayer(i) }
            }
        }
    }

    static func symbol(_ k: SkinManifest.Layer.Kind) -> String {
        switch k {
        case .stars: "sparkles"
        case .glow: "sun.max"
        case .swirl: "hurricane"
        case .flow: "wind"
        case .image: "photo"
        }
    }

    private var hint: String {
        guard let layer else { return "Adicione uma camada para começar." }
        if layer.kind == .flow { return "O vento ocupa a área toda: ajuste força e velocidade." }
        if layer.kind == .image { return "Clique para posicionar a imagem; arraste para mover." }
        return "Clique no palco para adicionar · arraste para mover · ⌫ apaga o ponto escolhido."
    }

    // MARK: Palco

    private var stage: some View {
        GeometryReader { geo in
            let theme = Theme(skin)
            let points = draft ?? layer?.points ?? []
            ZStack {
                LinearGradient(colors: [theme.windowTop, theme.windowBottom], startPoint: .top, endPoint: .bottom)
                if let art = theme.art {
                    SkinFillView(art: art, fill: skin.manifest.window.background, layers: liveLayers, energy: { 0.4 })
                }
                if usesPoints {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                        handle(p, size: geo.size, selected: i == selectedPoint)
                            .gesture(DragGesture(minimumDistance: 1)
                                .onChanged { g in
                                    selectedPoint = i
                                    var list = draft ?? points
                                    list[i].x = min(max(g.location.x / geo.size.width, 0), 1)
                                    list[i].y = min(max(g.location.y / geo.size.height, 0), 1)
                                    draft = list
                                }
                                .onEnded { _ in commitDraft() })
                            .onTapGesture { selectedPoint = i }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { at in
                guard usesPoints else { return }
                addPoint(x: at.x / geo.size.width, y: at.y / geo.size.height)
            }
        }
        .frame(width: 440, height: 304)   // proporção da janela do app
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
        .frame(maxWidth: .infinity)
        .onDeleteCommand { deletePoint() }
        .focusable()
    }

    /// Camadas com o rascunho do arrasto aplicado (o palco mostra o movimento na hora).
    private var liveLayers: [SkinManifest.Layer] {
        var list = layers.filter(\.enabled)
        if let draft, layers.indices.contains(selected), let i = list.firstIndex(where: { $0 == layers[selected] }) {
            list[i].points = draft
        }
        return list
    }

    private func handle(_ p: SkinManifest.Point, size: CGSize, selected: Bool) -> some View {
        let d = max(14, p.r * max(size.width, size.height) * 2)
        return Circle()
            .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.8), style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: [3, 3]))
            .background(Circle().fill(Color.black.opacity(0.001)))
            .frame(width: d, height: d)
            .position(x: p.x * size.width, y: p.y * size.height)
    }

    private func usesPointsFor(_ l: SkinManifest.Layer) -> Bool { l.kind != .flow }

    // MARK: Mudanças

    private func bind<T>(_ i: Int, _ key: WritableKeyPath<SkinManifest.Layer, T>) -> Binding<T> {
        Binding(get: { layers[i][keyPath: key] }, set: { v in update(i) { $0[keyPath: key] = v } })
    }

    private func update(_ i: Int, _ change: (inout SkinManifest.Layer) -> Void) {
        var m = skin.manifest
        guard m.window.layers.indices.contains(i) else { return }
        change(&m.window.layers[i])
        save(m)
    }

    private func add(_ kind: SkinManifest.Layer.Kind) {
        var m = skin.manifest
        var new = SkinManifest.Layer(kind: kind, color: kind == .glow ? "#FFE27A" : "#FFF2A0")
        switch kind {
        case .flow: new.count = 50; new.colors = ["#FFFFFF", "#BFD8FF"]; new.intensity = 0.45
        case .swirl: new.points = [.init(x: 0.5, y: 0.35, r: 0.12)]
        case .glow: new.points = [.init(x: 0.8, y: 0.2, r: 0.06)]
        case .stars: new.points = []
        case .image:
            guard let file = addImage() else { return }
            new.image = file; new.motion = "float"; new.intensity = 1; new.react = false
            new.points = [.init(x: 0.5, y: 0.5, r: 0.12)]
        }
        m.window.layers.append(new)
        save(m)
        selected = m.window.layers.count - 1
        selectedPoint = new.points.isEmpty ? nil : 0
    }

    private func addPoint(x: Double, y: Double) {
        guard var l = layer else { return }
        // Tamanho padrão do tipo (não o do último ponto: as estrelas grandes deixavam a nova enorme).
        let r = l.kind == .stars ? 0.012 : l.kind == .glow ? 0.05 : 0.1
        if l.kind == .image { l.points = [.init(x: x, y: y, r: l.points.first?.r ?? 0.12)] }
        else { l.points.append(.init(x: x, y: y, r: r)) }
        update(selected) { $0.points = l.points }
        selectedPoint = l.points.count - 1
    }

    private func deletePoint() {
        guard let p = selectedPoint, let l = layer, l.points.indices.contains(p) else { return }
        update(selected) { $0.points.remove(at: p) }
        selectedPoint = nil
    }

    private func commitDraft() {
        guard let points = draft else { return }
        draft = nil
        update(selected) { $0.points = points }
    }

    private func removeLayer(_ i: Int) {
        var m = skin.manifest
        guard m.window.layers.indices.contains(i) else { return }
        m.window.layers.remove(at: i)
        save(m)
        selected = max(0, min(selected, m.window.layers.count - 1))
        selectedPoint = nil
    }
}
