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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            stage
            HStack {
                Menu {
                    Button { add(.stars) } label: { Label("Estrelas cintilando", systemImage: "sparkles") }
                    Button { add(.glow) } label: { Label("Halo que respira (lua, sol, luz)", systemImage: "sun.max") }
                    Button { add(.swirl) } label: { Label("Redemoinho girando", systemImage: "hurricane") }
                    Button { add(.flow) } label: { Label("Vento de pinceladas", systemImage: "wind") }
                    Button { add(.image) } label: { Label("Imagem animada (personagem, logo)…", systemImage: "photo") }
                } label: { Label("Adicionar camada", systemImage: "plus") }
                    .fixedSize()
                Spacer()
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(layers.enumerated()), id: \.offset) { i, l in row(i, l) }
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
        .frame(width: 400, height: 276)   // proporção da janela do app
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

    // MARK: Lista de camadas

    private func row(_ i: Int, _ l: SkinManifest.Layer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { selected = i; selectedPoint = nil } label: {
                    Image(systemName: i == selected ? "largecircle.fill.circle" : "circle")
                }
                .buttonStyle(.borderless)
                .help("Editar esta camada no palco")
                Toggle("", isOn: bind(i, \.enabled)).labelsHidden()
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.name?.capitalized ?? SkinEditorView.kindName(l.kind)).font(.system(size: 12, weight: .medium))
                    Text(l.kind == .flow ? SkinEditorView.kindName(l.kind) : "\(SkinEditorView.kindName(l.kind)) · \(l.points.count) ponto(s)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if l.kind != .image {
                    ColorPicker("Cor", selection: Binding(get: { Color(hexString: l.color ?? l.colors.first ?? "#FFFFFF") ?? .white },
                                                          set: { c in update(i) { $0.color = c.hexString; $0.colors = [] } }), supportsOpacity: false)
                        .fixedSize()
                } else {
                    Picker("Movimento", selection: Binding(get: { l.motion ?? "float" }, set: { m in update(i) { $0.motion = m } })) {
                        Text("Flutua").tag("float"); Text("Gira").tag("spin"); Text("Pulsa").tag("pulse"); Text("Parada").tag("none")
                    }
                    .fixedSize()
                }
                Toggle("Reage à música", isOn: bind(i, \.react)).toggleStyle(.checkbox).fixedSize()
                Button { removeLayer(i) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Apagar camada")
            }
            HStack(spacing: 8) {
                Text("Força").font(.caption).foregroundStyle(.secondary).fixedSize()
                Slider(value: bind(i, \.intensity), in: 0...1)
                Text("Velocidade").font(.caption).foregroundStyle(.secondary).fixedSize()
                Slider(value: bind(i, \.speed), in: 0...3)
                if usesPointsFor(l), i == selected, let p = selectedPoint, l.points.indices.contains(p) {
                    Text("Tamanho do ponto").font(.caption).foregroundStyle(.secondary).fixedSize()
                    Slider(value: Binding(get: { l.points[p].r }, set: { v in update(i) { $0.points[p].r = v } }), in: 0.003...0.3)
                }
            }
            .padding(.leading, 30)
        }
        .opacity(l.enabled ? 1 : 0.5)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(i == selected ? Color.accentColor.opacity(0.1) : Color.white.opacity(0.03)))
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
