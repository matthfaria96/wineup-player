import AVFoundation
import AppKit
import SwiftUI

/// O que o painel da capa mostra: a capa ou uma cena animada que reage à música.
/// As cenas são desenhadas pelo app (sem imagens de terceiros); "Seus vídeos" toca clipes de uma pasta do usuário.
enum VisualMode: String, CaseIterable, Identifiable {
    case cover, aurora, fjord, city, universe, videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cover: "Capa da música"
        case .aurora: "Aurora na Noruega"
        case .fjord: "Fiorde ao entardecer (Suécia)"
        case .city: "Tour pela cidade à noite"
        case .universe: "Universo"
        case .videos: "Seus vídeos (anime, filmes…)"
        }
    }

    var symbol: String {
        switch self {
        case .cover: "photo"
        case .aurora: "sparkles"
        case .fjord: "mountain.2"
        case .city: "building.2"
        case .universe: "moon.stars"
        case .videos: "film"
        }
    }

    static let key = "artwork.visual"
    static let videoFolderKey = "artwork.videoFolder"
}

/// Cena animada (20 fps: cenas lentas não precisam de mais e o player fica leve). `energy` (0...1) vem do medidor: a cena acende e acelera com a música.
struct VisualScene: View {
    let mode: VisualMode
    let energy: () -> Double
    let seed: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let e = min(max(energy(), 0), 1)
            Canvas(opaque: true, rendersAsynchronously: true) { ctx, size in
                switch mode {
                case .aurora: Scenes.aurora(&ctx, size, t, e, seed)
                case .fjord: Scenes.fjord(&ctx, size, t, e, seed)
                case .city: Scenes.city(&ctx, size, t, e, seed)
                case .universe: Scenes.universe(&ctx, size, t, e, seed)
                default: break
                }
            }
        }
        .drawingGroup()
        .accessibilityLabel(mode.title)
    }
}

/// Desenho das cenas: só formas e gradientes (rápido e sem arquivos).
enum Scenes {
    /// Número pseudoaleatório estável (0...1) para posições de estrelas, janelas etc.
    static func rnd(_ i: Int, _ salt: Int) -> Double {
        var x = UInt64(bitPattern: Int64(i &* 73_856_093 ^ salt &* 19_349_663))
        x ^= x >> 33; x &*= 0xff51afd7ed558ccd; x ^= x >> 33; x &*= 0xc4ceb9fe1a85ec53; x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }

    static func sky(_ ctx: inout GraphicsContext, _ size: CGSize, _ colors: [Color]) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    static func stars(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, count: Int, maxY: Double, salt: Int) {
        for i in 0..<count {
            let x = rnd(i, salt) * size.width, y = rnd(i, salt + 1) * size.height * maxY
            let twinkle = 0.4 + 0.6 * abs(sin(t * (0.5 + rnd(i, salt + 2) * 2) + Double(i)))
            let r = 0.4 + rnd(i, salt + 3) * 1.1
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(twinkle * 0.9)))
        }
    }

    /// Montanhas: perfil por somas de senos, com deslocamento (parallax).
    static func mountains(_ ctx: inout GraphicsContext, _ size: CGSize, base: Double, height: Double,
                          offset: Double, salt: Int, color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: size.height))
        let step = max(size.width / 80, 2)
        var x = 0.0
        while x <= size.width + step {
            let u = (x + offset) / size.width
            let h = 0.5 * sin(u * 6.1 + Double(salt)) + 0.3 * sin(u * 13.7 + Double(salt) * 2) + 0.2 * sin(u * 29 + Double(salt) * 3)
            p.addLine(to: CGPoint(x: x, y: size.height * base - (h + 1) / 2 * size.height * height))
            x += step
        }
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.closeSubpath()
        ctx.fill(p, with: .color(color))
    }

    // MARK: Aurora na Noruega

    static func aurora(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ seed: Int) {
        sky(&ctx, size, [Color(hex: 0x020814), Color(hex: 0x071A2E), Color(hex: 0x0B2B3A)])
        stars(&ctx, size, t, count: 120, maxY: 0.7, salt: 11)
        // Cortinas da aurora: faixas verticais finas ao longo de uma curva que ondula.
        let curtains: [(Color, Double, Double)] = [(Color(hex: 0x39FF9E), 0.32, 0), (Color(hex: 0x7CFFCB), 0.42, 1.7),
                                                   (Color(hex: 0xB45CFF), 0.26, 3.1)]
        var layer = ctx
        layer.blendMode = .plusLighter
        for (k, (color, yBase, phase)) in curtains.enumerated() {
            let columns = 60
            for c in 0..<columns {
                let u = Double(c) / Double(columns)
                let x = u * size.width
                let wave = sin(u * 5 + t * 0.35 + phase) * 0.06 + sin(u * 11 - t * 0.6 + phase) * 0.03
                let top = size.height * (yBase + wave - 0.12)
                let len = size.height * (0.18 + 0.12 * sin(u * 7 + t * 0.8 + Double(k)) + e * 0.12)
                let alpha = (0.10 + 0.10 * sin(u * 17 + t * 1.3 + phase) + e * 0.25) * (k == 2 ? 0.7 : 1)
                let rect = CGRect(x: x, y: top, width: size.width / Double(columns) + 1, height: max(len, 1))
                layer.fill(Path(rect), with: .linearGradient(Gradient(colors: [color.opacity(0), color.opacity(max(alpha, 0)), color.opacity(0)]),
                                                             startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: top + len)))
            }
        }
        mountains(&ctx, size, base: 0.86, height: 0.22, offset: t * 2, salt: 3 + seed % 5, color: Color(hex: 0x061018))
        mountains(&ctx, size, base: 0.93, height: 0.14, offset: t * 5, salt: 7, color: Color(hex: 0x02060B))
        // Água com reflexo verde.
        let water = CGRect(x: 0, y: size.height * 0.93, width: size.width, height: size.height * 0.07)
        ctx.fill(Path(water), with: .linearGradient(Gradient(colors: [Color(hex: 0x0E3B33).opacity(0.6 + e * 0.3), .black]),
                                                     startPoint: CGPoint(x: 0, y: water.minY), endPoint: CGPoint(x: 0, y: water.maxY)))
    }

    // MARK: Fiorde ao entardecer

    static func fjord(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ seed: Int) {
        sky(&ctx, size, [Color(hex: 0x23305E), Color(hex: 0xC4607A), Color(hex: 0xFFB36B)])
        let horizon = size.height * 0.62
        let sun = CGPoint(x: size.width * 0.62, y: horizon - size.height * (0.06 + 0.02 * sin(t * 0.05)))
        let radius = size.width * (0.09 + e * 0.015)
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - radius * 2.5, y: sun.y - radius * 2.5, width: radius * 5, height: radius * 5)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xFFE7A8).opacity(0.55), .clear]), center: sun, startRadius: 0, endRadius: radius * 2.5))
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2)), with: .color(Color(hex: 0xFFF1C9)))
        mountains(&ctx, size, base: 0.66, height: 0.30, offset: t * 1.5, salt: 2 + seed % 4, color: Color(hex: 0x5B3A64).opacity(0.85))
        mountains(&ctx, size, base: 0.66, height: 0.20, offset: t * 4, salt: 9, color: Color(hex: 0x2E2346))
        // Lago: reflexo do céu e linhas de brilho que se mexem.
        let lake = CGRect(x: 0, y: horizon + size.height * 0.04, width: size.width, height: size.height)
        ctx.fill(Path(lake), with: .linearGradient(Gradient(colors: [Color(hex: 0xE7A07C), Color(hex: 0x3B3567)]),
                                                    startPoint: CGPoint(x: 0, y: lake.minY), endPoint: CGPoint(x: 0, y: size.height)))
        for i in 0..<40 {
            let y = lake.minY + rnd(i, 5) * (size.height - lake.minY)
            let w = size.width * (0.05 + rnd(i, 6) * 0.2) * (1 + e)
            let x = sun.x - w / 2 + sin(t * 0.8 + Double(i)) * size.width * 0.05
            ctx.fill(Path(CGRect(x: x, y: y, width: w, height: 1.2)), with: .color(Color(hex: 0xFFE4B5).opacity(0.25 + 0.3 * rnd(i, 7))))
        }
        // Pinheiros na margem, passando devagar.
        for i in 0..<14 {
            let x = (rnd(i, 8) * size.width * 1.4 - (t * 6).truncatingRemainder(dividingBy: size.width * 1.4) + size.width * 1.4)
                .truncatingRemainder(dividingBy: size.width * 1.4) - size.width * 0.2
            let h = size.height * (0.10 + rnd(i, 9) * 0.10)
            var tree = Path()
            tree.move(to: CGPoint(x: x, y: lake.minY - h))
            tree.addLine(to: CGPoint(x: x - h * 0.22, y: lake.minY))
            tree.addLine(to: CGPoint(x: x + h * 0.22, y: lake.minY))
            ctx.fill(tree, with: .color(Color(hex: 0x1A1430)))
        }
    }

    // MARK: Tour pela cidade à noite

    static func city(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ seed: Int) {
        sky(&ctx, size, [Color(hex: 0x05030F), Color(hex: 0x1A1038), Color(hex: 0x3D1F4F)])
        stars(&ctx, size, t, count: 50, maxY: 0.4, salt: 21)
        let moon = CGPoint(x: size.width * 0.8, y: size.height * 0.15)
        ctx.fill(Path(ellipseIn: CGRect(x: moon.x - 14, y: moon.y - 14, width: 28, height: 28)), with: .color(Color(hex: 0xF2EBD3).opacity(0.9)))
        // Três camadas de prédios em velocidades diferentes (passeio de carro).
        let layers: [(speed: Double, base: Double, maxH: Double, w: Double, color: Color, lit: Double)] = [
            (8, 0.78, 0.35, 0.10, Color(hex: 0x1B1530), 0.25),
            (22, 0.84, 0.42, 0.13, Color(hex: 0x120E22), 0.4),
            (55, 0.90, 0.50, 0.17, Color(hex: 0x0A0814), 0.55)]
        for (l, layer) in layers.enumerated() {
            let bw = size.width * layer.w
            let shift = (t * layer.speed * (1 + e)).truncatingRemainder(dividingBy: bw)
            let first = Int(floor(t * layer.speed * (1 + e) / bw))
            for k in 0...Int(size.width / bw) + 1 {
                let index = first + k
                let x = Double(k) * bw - shift
                let h = size.height * layer.maxH * (0.35 + rnd(index, 30 + l) * 0.65)
                let top = size.height * layer.base - h
                ctx.fill(Path(CGRect(x: x, y: top, width: bw - 3, height: h)), with: .color(layer.color))
                // Janelas acesas (piscam devagar; com a música, mais janelas).
                let cols = 3, rows = Int(h / 12)
                for r in 0..<max(rows, 0) {
                    for c in 0..<cols {
                        let id = index * 997 + r * 13 + c
                        guard rnd(id, 40 + l) < layer.lit + e * 0.25 else { continue }
                        let flicker = 0.6 + 0.4 * sin(t * 0.7 + Double(id))
                        ctx.fill(Path(CGRect(x: x + 5 + Double(c) * (bw - 10) / Double(cols), y: top + 6 + Double(r) * 12, width: 4, height: 5)),
                                 with: .color(Color(hex: rnd(id, 41) < 0.8 ? 0xFFD27A : 0x8FD3FF).opacity(flicker)))
                    }
                }
            }
        }
        // Rua com faróis e lanternas passando.
        let road = CGRect(x: 0, y: size.height * 0.9, width: size.width, height: size.height * 0.1)
        ctx.fill(Path(road), with: .color(Color(hex: 0x06050B)))
        for i in 0..<10 {
            let speed = 80 + rnd(i, 50) * 80
            let x = (rnd(i, 51) * size.width + t * speed * (1 + e)).truncatingRemainder(dividingBy: size.width + 40) - 20
            let toRight = i % 2 == 0
            let y = road.minY + (toRight ? road.height * 0.35 : road.height * 0.7)
            let color = toRight ? Color(hex: 0xFFF3C4) : Color(hex: 0xFF3B30)
            let px = toRight ? x : size.width - x
            ctx.fill(Path(ellipseIn: CGRect(x: px, y: y, width: 10, height: 3)), with: .color(color.opacity(0.9)))
        }
    }

    // MARK: Universo

    static func universe(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ seed: Int) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x020109)))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Nebulosas girando devagar.
        var glow = ctx
        glow.blendMode = .plusLighter
        let nebulae: [(Color, Double)] = [(Color(hex: 0x6A2BD9), 0), (Color(hex: 0x1E8FD9), 2.1), (Color(hex: 0xD92B7A), 4.2)]
        for (color, phase) in nebulae {
            let a = t * 0.05 + phase + Double(seed % 7)
            let p = CGPoint(x: center.x + cos(a) * size.width * 0.22, y: center.y + sin(a * 1.3) * size.height * 0.18)
            let r = size.width * (0.45 + e * 0.1)
            glow.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                      with: .radialGradient(Gradient(colors: [color.opacity(0.35 + e * 0.2), .clear]), center: p, startRadius: 0, endRadius: r))
        }
        // Estrelas vindo na direção da tela (dobra espacial); a música acelera.
        let maxR = hypot(size.width, size.height) / 2
        for i in 0..<160 {
            let angle = rnd(i, 60) * 2 * .pi
            let speed = 0.05 + rnd(i, 61) * 0.12
            let z = (rnd(i, 62) + t * speed * (1 + e * 3)).truncatingRemainder(dividingBy: 1)
            let r = pow(z, 2.2) * maxR
            let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            let tail = r * (0.04 + e * 0.12)
            var line = Path()
            line.move(to: p)
            line.addLine(to: CGPoint(x: p.x - cos(angle) * tail, y: p.y - sin(angle) * tail))
            ctx.stroke(line, with: .color(.white.opacity(min(1, z * 1.4))), lineWidth: 0.6 + z * 1.6)
        }
    }
}

/// "Seus vídeos": clipes de uma pasta do usuário, sem som, em loop; troca a cada música.
struct VideoWall: NSViewRepresentable {
    let folder: URL?
    let trackKey: Int

    final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var lastKey: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: context.coordinator.player)
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = layer
        context.coordinator.player.isMuted = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator
        guard c.lastKey != trackKey else { return }
        c.lastKey = trackKey
        guard let url = Self.videos(in: folder).randomElement() else { c.player.removeAllItems(); return }
        let item = AVPlayerItem(url: url)
        c.looper = AVPlayerLooper(player: c.player, templateItem: item)
        c.player.play()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.looper = nil
    }

    static func videos(in folder: URL?) -> [URL] {
        guard let folder else { return [] }
        let exts: Set<String> = ["mp4", "m4v", "mov"]
        let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return (e?.allObjects as? [URL] ?? []).filter { exts.contains($0.pathExtension.lowercased()) }
    }
}
