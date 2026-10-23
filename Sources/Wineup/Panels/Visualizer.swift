import AVFoundation
import AppKit
import SwiftUI

/// O que o painel da capa mostra: a capa ou uma cena animada que reage à música.
/// As cenas são desenhadas pelo app (sem imagens de terceiros); "Seus vídeos" toca clipes de uma pasta do usuário.
enum VisualMode: String, CaseIterable, Identifiable {
    case cover, skinArt, aurora, fjord, city, universe, videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cover: "Capa da música"
        case .skinArt: "Arte do skin"
        case .aurora: "Aurora na Noruega"
        case .fjord: "Noite de verão na Suécia"
        case .city: "Cidade à noite"
        case .universe: "Galáxia"
        case .videos: "Vídeos"
        }
    }

    var symbol: String {
        switch self {
        case .cover: "photo"
        case .skinArt: "paintpalette"
        case .aurora: "sparkles"
        case .fjord: "leaf"
        case .city: "building.2"
        case .universe: "sparkle"
        case .videos: "film"
        }
    }

    static let key = "artwork.visual"
}

/// Cena animada (20 fps: cenas lentas não precisam de mais e o player fica leve). `energy` (0...1) vem do medidor: a cena acende e acelera com a música.
struct VisualScene: View {
    let mode: VisualMode
    let energy: () -> Double
    let seed: Int
    @StateObject private var smooth = SmoothEnergy()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // A música só "respira" na cena: valor suavizado e com pouco peso (nada de pular).
            let e = smooth.next(energy()) * 0.35
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

/// Média móvel lenta do volume (~1,5 s): a cena acompanha a música sem tremer.
final class SmoothEnergy: ObservableObject {
    private var value = 0.0
    func next(_ target: Double) -> Double {
        value += (min(max(target, 0), 1) - value) * 0.03
        return value
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

    // MARK: Noite clara de verão na Suécia (sol da meia-noite, lago espelhado, névoa, pinheiros)

    static func fjord(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ seed: Int) {
        // Céu do sol da meia-noite: azul-petróleo em cima, rosa-pálido e âmbar baixos no horizonte.
        sky(&ctx, size, [Color(hex: 0x0B1B2B), Color(hex: 0x1F3A4E), Color(hex: 0x6E6A7C), Color(hex: 0xC99A8A)])
        stars(&ctx, size, t, count: 30, maxY: 0.35, salt: 51)
        let horizon = size.height * 0.6
        // Sol baixo, quase escondido, com halo que respira devagar.
        let sun = CGPoint(x: size.width * 0.66, y: horizon - size.height * 0.015)
        let halo = size.width * (0.28 + 0.02 * sin(t * 0.15) + e * 0.05)
        var glow = ctx
        glow.blendMode = .plusLighter
        glow.fill(Path(ellipseIn: CGRect(x: sun.x - halo, y: sun.y - halo * 0.6, width: halo * 2, height: halo * 1.2)),
                  with: .radialGradient(Gradient(colors: [Color(hex: 0xFFC9A0).opacity(0.35), Color(hex: 0xC97C7C).opacity(0.12), .clear]),
                                        center: sun, startRadius: 0, endRadius: halo))
        // Montanhas distantes em camadas azuladas (atmosfera).
        mountains(&ctx, size, base: 0.6, height: 0.16, offset: t * 0.6, salt: 4 + seed % 3, color: Color(hex: 0x2D3E54).opacity(0.9))
        mountains(&ctx, size, base: 0.61, height: 0.10, offset: t * 1.2, salt: 12, color: Color(hex: 0x1B2638))
        // Lago espelhado: o céu invertido e escurecido, com linhas de luz lentas.
        let lake = CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)
        ctx.fill(Path(lake), with: .linearGradient(Gradient(colors: [Color(hex: 0x8E7480).opacity(0.85), Color(hex: 0x2A3A4C), Color(hex: 0x081320)]),
                                                    startPoint: CGPoint(x: 0, y: lake.minY), endPoint: CGPoint(x: 0, y: lake.maxY)))
        for i in 0..<28 {
            let y = lake.minY + pow(rnd(i, 52), 1.6) * lake.height
            let w = size.width * (0.04 + rnd(i, 53) * 0.16)
            let x = sun.x - w / 2 + sin(t * 0.25 + Double(i)) * size.width * 0.03
            let a = (1 - (y - lake.minY) / lake.height) * (0.22 + e * 0.3)
            glow.fill(Path(CGRect(x: x, y: y, width: w, height: 1)), with: .color(Color(hex: 0xFFD2B0).opacity(a)))
        }
        // Névoa rasteira passando sobre a água.
        for k in 0..<3 {
            let y = horizon + size.height * (0.01 + Double(k) * 0.035)
            let drift = (t * (4 + Double(k) * 2)).truncatingRemainder(dividingBy: size.width * 2) - size.width
            ctx.fill(Path(ellipseIn: CGRect(x: drift, y: y, width: size.width * 1.6, height: size.height * 0.05)),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xC8C4D6).opacity(0.10), .clear]),
                                           center: CGPoint(x: drift + size.width * 0.8, y: y + size.height * 0.025),
                                           startRadius: 0, endRadius: size.width * 0.8))
        }
        // Margem com pinheiros em silhueta (e o reflexo deles, mais claro).
        let shore = horizon + size.height * 0.004
        for i in 0..<22 {
            let x = rnd(i, 54) * size.width
            let h = size.height * (0.06 + rnd(i, 55) * 0.13) * (x < size.width * 0.35 ? 1.2 : 0.8)
            for (dir, alpha) in [(-1.0, 1.0), (1.0, 0.22)] {
                var tree = Path()
                tree.move(to: CGPoint(x: x, y: shore + dir * h))
                tree.addLine(to: CGPoint(x: x - h * 0.18, y: shore))
                tree.addLine(to: CGPoint(x: x + h * 0.18, y: shore))
                ctx.fill(tree, with: .color(Color(hex: 0x060B12).opacity(alpha)))
            }
        }
    }

    static func clouds(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, count: Int, band: ClosedRange<Double>, salt: Int, speed: Double) {}

    // MARK: Cidade à noite à beira d'água (skyline em silhueta, janelas, reflexo e bokeh)

    static func city(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ seed: Int) {
        sky(&ctx, size, [Color(hex: 0x050816), Color(hex: 0x111A33), Color(hex: 0x2B2346), Color(hex: 0x6A3F5C)])
        stars(&ctx, size, t, count: 25, maxY: 0.3, salt: 61)
        let horizon = size.height * 0.62
        // Brilho da cidade no céu, baixo e quente.
        var glow = ctx
        glow.blendMode = .plusLighter
        glow.fill(Path(CGRect(x: 0, y: horizon - size.height * 0.3, width: size.width, height: size.height * 0.3)),
                  with: .linearGradient(Gradient(colors: [.clear, Color(hex: 0xE58A6A).opacity(0.18 + e * 0.15)]),
                                        startPoint: CGPoint(x: 0, y: horizon - size.height * 0.3), endPoint: CGPoint(x: 0, y: horizon)))
        // Duas camadas de prédios em silhueta, passando bem devagar.
        let layers: [(speed: Double, maxH: Double, w: Double, color: UInt32, lit: Double)] = [
            (1.5, 0.30, 0.07, 0x161C30, 0.18), (4, 0.42, 0.10, 0x0A0E1C, 0.3)]
        var windows: [(CGRect, Double)] = []
        for (l, layer) in layers.enumerated() {
            let bw = size.width * layer.w
            let travel = t * layer.speed
            let shift = travel.truncatingRemainder(dividingBy: bw), first = Int(floor(travel / bw))
            for k in 0...Int(size.width / bw) + 1 {
                let index = first + k, x = Double(k) * bw - shift
                let h = size.height * layer.maxH * (0.3 + rnd(index, 62 + l) * 0.7), top = horizon - h
                ctx.fill(Path(CGRect(x: x, y: top, width: bw - 2, height: h)), with: .color(Color(hex: layer.color)))
                let rows = Int(h / 9)
                for r in 0..<max(rows, 0) { for c in 0..<3 {
                    let id = index * 131 + r * 7 + c
                    guard rnd(id, 70 + l) < layer.lit else { continue }
                    let flicker = 0.55 + 0.45 * sin(t * 0.08 + Double(id))
                    windows.append((CGRect(x: x + 4 + Double(c) * (bw - 8) / 3, y: top + 5 + Double(r) * 9, width: 2.5, height: 3.5), flicker))
                } }
            }
        }
        for (rect, a) in windows { glow.fill(Path(rect), with: .color(Color(hex: 0xFFCF8A).opacity(a * 0.9))) }
        // Água: reflexo escuro, luzes esticadas tremendo devagar.
        let water = CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)
        ctx.fill(Path(water), with: .linearGradient(Gradient(colors: [Color(hex: 0x1A1730), Color(hex: 0x05060E)]),
                                                     startPoint: CGPoint(x: 0, y: water.minY), endPoint: CGPoint(x: 0, y: water.maxY)))
        for (i, (rect, a)) in windows.enumerated() where i % 3 == 0 {
            let depth = horizon - rect.minY
            let y = horizon + depth * 0.9
            guard y < size.height else { continue }
            let wobble = sin(t * 0.6 + Double(i)) * 2
            glow.fill(Path(CGRect(x: rect.minX + wobble, y: y, width: rect.width, height: 6)),
                      with: .color(Color(hex: 0xFFB36B).opacity(a * 0.25 * (1 - depth / size.height))))
        }
        // Bokeh: luzes desfocadas flutuando no primeiro plano.
        for i in 0..<14 {
            let x = (rnd(i, 80) * size.width + t * (3 + rnd(i, 81) * 4)).truncatingRemainder(dividingBy: size.width + 80) - 40
            let y = size.height * (0.55 + rnd(i, 82) * 0.4) + sin(t * 0.2 + Double(i)) * 6
            let r = 14 + rnd(i, 83) * 26
            let c = [Color(hex: 0xFFB36B), Color(hex: 0xE58AB0), Color(hex: 0x8AB4FF)][i % 3]
            glow.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                      with: .radialGradient(Gradient(colors: [c.opacity(0.16 + e * 0.2), .clear]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        }
    }

    // MARK: Galáxia (espiral serena, poeira e estrelas em profundidade)

    static func universe(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ seed: Int) {
        sky(&ctx, size, [Color(hex: 0x02030A), Color(hex: 0x070A1C), Color(hex: 0x0C0718)])
        // Estrelas de fundo em três profundidades, com deriva lenta (sensação de viagem).
        for layer in 0..<3 {
            let n = [120, 60, 25][layer], speed = [0.6, 1.4, 3.0][layer]
            for i in 0..<n {
                let x = (rnd(i, 90 + layer) * size.width + t * speed).truncatingRemainder(dividingBy: size.width)
                let y = rnd(i, 93 + layer) * size.height
                let r = [0.6, 1.0, 1.6][layer] * (0.7 + rnd(i, 96) * 0.6)
                let tw = 0.5 + 0.5 * sin(t * (0.4 + rnd(i, 97)) + Double(i))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.3 + tw * 0.5)))
            }
        }
        let center = CGPoint(x: size.width * 0.52, y: size.height * 0.5)
        let radius = min(size.width, size.height) * 0.52
        let spin = t * 0.02 + Double(seed % 7)
        var glow = ctx
        glow.blendMode = .plusLighter
        // Halo difuso e núcleo quente.
        glow.fill(Path(ellipseIn: CGRect(x: center.x - radius * 1.3, y: center.y - radius * 0.8, width: radius * 2.6, height: radius * 1.6)),
                  with: .radialGradient(Gradient(colors: [Color(hex: 0x6B5BD6).opacity(0.18), Color(hex: 0x2B1E5A).opacity(0.08), .clear]),
                                        center: center, startRadius: 0, endRadius: radius * 1.3))
        glow.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.35, y: center.y - radius * 0.22, width: radius * 0.7, height: radius * 0.44)),
                  with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF1D8).opacity(0.75 + e), Color(hex: 0xF0A870).opacity(0.25), .clear]),
                                        center: center, startRadius: 0, endRadius: radius * 0.35))
        // Braços: milhares de pontinhos ao longo de duas espirais logarítmicas, inclinadas (perspectiva).
        let palette = [Color(hex: 0x9FC4FF), Color(hex: 0xC8A8FF), Color(hex: 0xFFC8E6), Color(hex: 0xFFFFFF)]
        for arm in 0..<2 {
            for i in 0..<700 {
                let u = rnd(i, 100 + arm)
                let r = radius * (0.08 + pow(u, 0.6) * 0.92)
                let theta = log(r / radius * 8 + 1) * 1.7 + Double(arm) * .pi + spin + (rnd(i, 102 + arm) - 0.5) * (0.5 + u * 0.6)
                let p = CGPoint(x: center.x + cos(theta) * r, y: center.y + sin(theta) * r * 0.42)
                let sz = 0.6 + rnd(i, 104) * 1.6
                let a = (1 - u) * 0.6 + 0.12
                glow.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: sz, height: sz)), with: .color(palette[i % 4].opacity(a)))
            }
        }
        // Nuvens de poeira (nebulosa) suaves sobre os braços.
        for i in 0..<10 {
            let u = rnd(i, 110)
            let r = radius * (0.25 + u * 0.7)
            let theta = log(r / radius * 8 + 1) * 1.7 + Double(i % 2) * .pi + spin
            let p = CGPoint(x: center.x + cos(theta) * r, y: center.y + sin(theta) * r * 0.42)
            let b = radius * (0.18 + rnd(i, 111) * 0.15)
            glow.fill(Path(ellipseIn: CGRect(x: p.x - b, y: p.y - b * 0.5, width: b * 2, height: b)),
                      with: .radialGradient(Gradient(colors: [[Color(hex: 0x7A5CFF), Color(hex: 0xFF6FB0), Color(hex: 0x4FA8FF)][i % 3].opacity(0.10), .clear]),
                                            center: p, startRadius: 0, endRadius: b))
        }
    }

}
