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
        case .fjord: "Verão na Suécia"
        case .city: "Cidade à beira-mar"
        case .universe: "Galáxia"
        case .videos: "Vídeos"
        }
    }

    var symbol: String {
        switch self {
        case .cover: "photo"
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

    // MARK: Verão na Suécia (campo verde, lago e casinha vermelha)

    static func fjord(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ seed: Int) {
        sky(&ctx, size, [Color(hex: 0x3C8DDE), Color(hex: 0x8CC8F2), Color(hex: 0xDFF1FB)])
        // Sol e nuvens fofas passando devagar.
        let sun = CGPoint(x: size.width * 0.22, y: size.height * 0.16)
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 60, y: sun.y - 60, width: 120, height: 120)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF6C8).opacity(0.9), .clear]), center: sun, startRadius: 0, endRadius: 60))
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 16, y: sun.y - 16, width: 32, height: 32)), with: .color(Color(hex: 0xFFFBE6)))
        clouds(&ctx, size, t, count: 6, band: 0.08...0.34, salt: 70, speed: 6)
        // Montanhas azuladas ao fundo, depois morros verdes em camadas (parallax), cada vez mais vivos.
        mountains(&ctx, size, base: 0.50, height: 0.16, offset: t * 1, salt: 4 + seed % 3, color: Color(hex: 0x7FB2D9))
        let hills: [(Double, Double, Double, UInt32)] = [(0.58, 0.14, 3, 0x4F9E4A), (0.70, 0.14, 7, 0x5FB54E), (0.86, 0.16, 14, 0x74C95A)]
        for (i, h) in hills.enumerated() {
            mountains(&ctx, size, base: h.0, height: h.1, offset: t * h.2, salt: 20 + i, color: Color(hex: h.3))
        }
        // Lago no meio, com reflexo do céu e ondulações que brilham com a música.
        let lake = CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.12)
        ctx.fill(Path(lake), with: .linearGradient(Gradient(colors: [Color(hex: 0x6FB7E8), Color(hex: 0x3F8ACB)]),
                                                    startPoint: CGPoint(x: 0, y: lake.minY), endPoint: CGPoint(x: 0, y: lake.maxY)))
        for i in 0..<25 {
            let y = lake.minY + rnd(i, 71) * lake.height
            let w = size.width * (0.04 + rnd(i, 72) * 0.12) * (1 + e)
            let x = rnd(i, 73) * size.width + sin(t * 0.7 + Double(i)) * 10
            ctx.fill(Path(CGRect(x: x, y: y, width: w, height: 1.2)), with: .color(.white.opacity(0.25 + 0.3 * rnd(i, 74))))
        }
        // Casinha vermelha sueca (falu röd) com janelas brancas.
        let hx = size.width * 0.68, hy = size.height * 0.79, hw = size.width * 0.12, hh = size.height * 0.08
        ctx.fill(Path(CGRect(x: hx, y: hy - hh, width: hw, height: hh)), with: .color(Color(hex: 0xA3271D)))
        var roof = Path(); roof.move(to: CGPoint(x: hx - hw * 0.08, y: hy - hh)); roof.addLine(to: CGPoint(x: hx + hw / 2, y: hy - hh * 1.7)); roof.addLine(to: CGPoint(x: hx + hw * 1.08, y: hy - hh)); roof.closeSubpath()
        ctx.fill(roof, with: .color(Color(hex: 0x3A2A28)))
        for k in 0..<2 {
            ctx.fill(Path(CGRect(x: hx + hw * (0.18 + Double(k) * 0.45), y: hy - hh * 0.75, width: hw * 0.2, height: hh * 0.35)), with: .color(Color(hex: 0xFFF7D6)))
        }
        // Bétulas (tronco branco, copa verde-clara) balançando de leve, e flores no campo.
        for i in 0..<9 {
            let x = rnd(i, 75) * size.width, baseY = size.height * (0.80 + rnd(i, 76) * 0.14)
            let h = size.height * (0.10 + rnd(i, 77) * 0.08), sway = sin(t * 0.9 + Double(i)) * (2 + e * 4)
            ctx.fill(Path(CGRect(x: x - 1.5, y: baseY - h, width: 3, height: h)), with: .color(Color(hex: 0xF2F2EE)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - h * 0.35 + sway, y: baseY - h * 1.25, width: h * 0.7, height: h * 0.6)), with: .color(Color(hex: 0x9BE37A).opacity(0.95)))
        }
        for i in 0..<60 {
            let x = rnd(i, 78) * size.width, y = size.height * (0.76 + rnd(i, 79) * 0.22)
            let c: UInt32 = [0xFFFFFF, 0xFFE566, 0xFF7AB5, 0xC77DFF][i % 4]
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y + sin(t * 1.5 + Double(i)) * 1, width: 3, height: 3)), with: .color(Color(hex: c)))
        }
    }

    static func clouds(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, count: Int, band: ClosedRange<Double>, salt: Int, speed: Double) {
        for i in 0..<count {
            let w = size.width * (0.18 + rnd(i, salt) * 0.2), h = w * 0.35
            let x = (rnd(i, salt + 1) * (size.width + w) + t * speed * (0.5 + rnd(i, salt + 2))).truncatingRemainder(dividingBy: size.width + w) - w
            let y = size.height * (band.lowerBound + rnd(i, salt + 3) * (band.upperBound - band.lowerBound))
            var p = Path()
            p.addEllipse(in: CGRect(x: x, y: y, width: w, height: h))
            p.addEllipse(in: CGRect(x: x + w * 0.25, y: y - h * 0.45, width: w * 0.55, height: h * 1.2))
            p.addEllipse(in: CGRect(x: x + w * 0.5, y: y - h * 0.1, width: w * 0.5, height: h))
            ctx.fill(p, with: .color(.white.opacity(0.92)))
        }
    }

    // MARK: Cidade de dia (orla, prédios coloridos, montanhas)

    static func city(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ seed: Int) {
        sky(&ctx, size, [Color(hex: 0x2F7FD6), Color(hex: 0x7CC0F0), Color(hex: 0xF7E1C3)])
        let sun = CGPoint(x: size.width * 0.78, y: size.height * 0.2)
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 70, y: sun.y - 70, width: 140, height: 140)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF0B8).opacity(0.8), .clear]), center: sun, startRadius: 0, endRadius: 70))
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 18, y: sun.y - 18, width: 36, height: 36)), with: .color(Color(hex: 0xFFFDF0)))
        clouds(&ctx, size, t, count: 5, band: 0.06...0.3, salt: 80, speed: 8)
        mountains(&ctx, size, base: 0.56, height: 0.22, offset: t * 1.2, salt: 5 + seed % 3, color: Color(hex: 0x6FA3C9))
        mountains(&ctx, size, base: 0.58, height: 0.14, offset: t * 2.5, salt: 11, color: Color(hex: 0x5C8FB3))
        // Pássaros passando.
        for i in 0..<6 {
            let x = (rnd(i, 81) * size.width + t * (18 + rnd(i, 82) * 12)).truncatingRemainder(dividingBy: size.width + 40) - 20
            let y = size.height * (0.12 + rnd(i, 83) * 0.25) + sin(t * 3 + Double(i)) * 3
            var b = Path(); b.move(to: CGPoint(x: x - 5, y: y)); b.addQuadCurve(to: CGPoint(x: x, y: y - 2), control: CGPoint(x: x - 2.5, y: y - 4)); b.addQuadCurve(to: CGPoint(x: x + 5, y: y), control: CGPoint(x: x + 2.5, y: y - 4))
            ctx.stroke(b, with: .color(Color(hex: 0x24364A).opacity(0.7)), lineWidth: 1.2)
        }
        // Prédios coloridos (tons pastel e vidro) em duas camadas, passando devagar.
        let palette: [UInt32] = [0xF2C4A0, 0xE8A598, 0xBFD7EA, 0xF6E3B4, 0xA9D3C5, 0xD9C7EB, 0x9FB8D8, 0xF0B8C8]
        let layers: [(speed: Double, base: Double, maxH: Double, w: Double, dim: Double)] = [(6, 0.66, 0.30, 0.09, 0.78), (16, 0.72, 0.36, 0.12, 1)]
        for (l, layer) in layers.enumerated() {
            let bw = size.width * layer.w
            let travel = t * layer.speed * (1 + e * 0.5)
            let shift = travel.truncatingRemainder(dividingBy: bw), first = Int(floor(travel / bw))
            for k in 0...Int(size.width / bw) + 1 {
                let index = first + k, x = Double(k) * bw - shift
                let h = size.height * layer.maxH * (0.35 + rnd(index, 90 + l) * 0.65), top = size.height * layer.base - h
                let color = Color(hex: palette[abs(index) % palette.count]).opacity(layer.dim)
                ctx.fill(Path(CGRect(x: x, y: top, width: bw - 4, height: h)), with: .color(color))
                ctx.fill(Path(CGRect(x: x, y: top, width: (bw - 4) * 0.3, height: h)), with: .color(.white.opacity(0.18)))
                let cols = 3, rows = Int(h / 14)
                for r in 0..<max(rows, 0) { for c in 0..<cols {
                    let id = index * 97 + r * 7 + c
                    let glint = 0.25 + 0.35 * max(0, sin(t * 0.6 + Double(id))) + e * 0.2
                    ctx.fill(Path(CGRect(x: x + 5 + Double(c) * (bw - 10) / Double(cols), y: top + 7 + Double(r) * 14, width: 4, height: 6)),
                             with: .color(Color(hex: 0x3B5B7A).opacity(0.55 + glint * 0.3)))
                } }
            }
        }
        // Orla: mar azul com brilho e um calçadão com árvores.
        let sea = CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.16)
        ctx.fill(Path(sea), with: .linearGradient(Gradient(colors: [Color(hex: 0x5FB6E8), Color(hex: 0x2F86C7)]), startPoint: CGPoint(x: 0, y: sea.minY), endPoint: CGPoint(x: 0, y: sea.maxY)))
        for i in 0..<30 {
            let y = sea.minY + rnd(i, 95) * sea.height, w = size.width * (0.03 + rnd(i, 96) * 0.1) * (1 + e)
            let x = (rnd(i, 97) * size.width + t * 12).truncatingRemainder(dividingBy: size.width + w) - w / 2
            ctx.fill(Path(CGRect(x: x, y: y, width: w, height: 1.2)), with: .color(.white.opacity(0.35 + 0.3 * rnd(i, 98))))
        }
        ctx.fill(Path(CGRect(x: 0, y: sea.maxY, width: size.width, height: size.height - sea.maxY)), with: .color(Color(hex: 0xE9D8B8)))
        for i in 0..<12 {
            let x = (rnd(i, 99) * size.width * 1.2 + t * 20).truncatingRemainder(dividingBy: size.width * 1.2) - size.width * 0.1
            let y = sea.maxY + 2, h = size.height * 0.07
            ctx.fill(Path(CGRect(x: x - 1, y: y - h * 0.3, width: 2, height: h * 0.5)), with: .color(Color(hex: 0x7A5A3A)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - h * 0.35, y: y - h * 0.9 + sin(t + Double(i)) * 1.5, width: h * 0.7, height: h * 0.7)), with: .color(Color(hex: 0x4FAE5C)))
        }
    }

    // MARK: Galáxia (espiral colorida girando)

    static func universe(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ seed: Int) {
        sky(&ctx, size, [Color(hex: 0x05021A), Color(hex: 0x0B0430), Color(hex: 0x1A0636)])
        stars(&ctx, size, t, count: 90, maxY: 1, salt: 100)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.46
        let spin = t * 0.08 * (1 + e * 0.6)
        var glow = ctx
        glow.blendMode = .plusLighter
        // Núcleo quente e nebulosas de cor viva nos braços.
        glow.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.5, y: center.y - radius * 0.5, width: radius, height: radius)),
                  with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF1C2).opacity(0.95), Color(hex: 0xFF9A5C).opacity(0.5), .clear]), center: center, startRadius: 0, endRadius: radius * 0.5))
        let armColors: [UInt32] = [0x4FD1FF, 0xFF4FA3, 0xB967FF, 0x5CFFB1]
        for arm in 0..<4 {
            let phase = Double(arm) * .pi / 2
            for i in 0..<110 {
                let u = Double(i) / 110, r = radius * (0.08 + u * 0.92)
                let a = phase + spin + u * 4.2 + rnd(i, 110 + arm) * 0.25
                let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r * 0.62)
                let blob = (6 + u * 14) * (1 + e * 0.5)
                let alpha = (1 - u) * 0.22 + 0.06 + e * 0.1
                glow.fill(Path(ellipseIn: CGRect(x: p.x - blob, y: p.y - blob, width: blob * 2, height: blob * 2)),
                          with: .radialGradient(Gradient(colors: [Color(hex: armColors[arm]).opacity(alpha), .clear]), center: p, startRadius: 0, endRadius: blob))
            }
        }
        // Estrelas dos braços, coloridas, piscando com a batida.
        for i in 0..<320 {
            let arm = i % 4, u = rnd(i, 120), r = radius * (0.05 + u * 0.95)
            let a = Double(arm) * .pi / 2 + spin + u * 4.2 + (rnd(i, 121) - 0.5) * 0.7
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r * 0.62)
            let tw = 0.5 + 0.5 * abs(sin(t * (1 + rnd(i, 122) * 3) + Double(i)))
            let c: UInt32 = [0xFFFFFF, 0xBFE8FF, 0xFFD6A0, 0xFFB3E6][i % 4]
            let sz = 0.8 + rnd(i, 123) * 1.8 + e * 1.2
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - sz / 2, y: p.y - sz / 2, width: sz, height: sz)), with: .color(Color(hex: c).opacity(0.5 + tw * 0.5)))
        }
    }
}
