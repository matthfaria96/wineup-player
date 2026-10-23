import AppKit
import SwiftUI
import WineupLibrary

/// Fundo de uma área do skin: imagem (recorte com foco), escurecida, e as camadas animadas por cima.
struct SkinFillView: View {
    let art: SkinArt
    let fill: SkinManifest.Fill?
    let layers: [SkinManifest.Layer]
    let energy: () -> Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let fill, let image = art.image(fill.image) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height,
                               alignment: Alignment(horizontal: fill.focusX < 0.34 ? .leading : fill.focusX > 0.66 ? .trailing : .center,
                                                    vertical: fill.focusY < 0.34 ? .top : fill.focusY > 0.66 ? .bottom : .center))
                        .clipped()
                        .blur(radius: fill.blur)
                        // A imagem é maior que a área (preenchimento): sem isto, a parte cortada
                        // continuaria recebendo cliques por cima de outros controles (ex.: a busca).
                        .allowsHitTesting(false)
                    Color.black.opacity(fill.dim)
                }
                let active = layers.filter(\.enabled)
                if !active.isEmpty {
                    SkinLayersView(art: art, layers: active, energy: energy)
                        .allowsHitTesting(false)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

/// Camadas animadas (20 fps). Desenho por formas e gradientes, composto pela GPU.
struct SkinLayersView: View {
    let art: SkinArt
    let layers: [SkinManifest.Layer]
    let energy: () -> Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let e = min(max(energy(), 0), 1)
            Canvas(rendersAsynchronously: true) { ctx, size in
                for (i, layer) in layers.enumerated() {
                    let boost = layer.react ? e : 0
                    switch layer.kind {
                    case .stars: LayerArt.stars(&ctx, size, t, boost, layer, salt: i)
                    case .swirl: LayerArt.swirls(&ctx, size, t, boost, layer)
                    case .glow: LayerArt.glows(&ctx, size, t, boost, layer)
                    case .flow: LayerArt.flow(&ctx, size, t, boost, layer, salt: i)
                    case .image: LayerArt.image(&ctx, size, t, boost, layer, art.image(layer.image))
                    }
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// Desenho de cada tipo de camada.
enum LayerArt {
    static func color(_ hex: String?, _ fallback: Color = .white) -> Color { hex.flatMap(Color.init(hexString:)) ?? fallback }

    static func palette(_ layer: SkinManifest.Layer) -> [Color] {
        let list = layer.colors.compactMap(Color.init(hexString:))
        return list.isEmpty ? [color(layer.color)] : list
    }

    /// Estrelas que pulsam: halo, núcleo e quatro raios que giram devagar.
    static func stars(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ layer: SkinManifest.Layer, salt: Int) {
        var points = layer.points
        if points.isEmpty {
            points = (0..<(layer.count ?? 30)).map {
                SkinManifest.Point(x: Scenes.rnd($0, 300 + salt), y: Scenes.rnd($0, 301 + salt), r: 0.004 + Scenes.rnd($0, 302 + salt) * 0.01)
            }
        }
        let tint = color(layer.color, Color(hex: 0xFFF2A0))
        var glow = ctx
        glow.blendMode = .plusLighter
        let unit = max(size.width, size.height)
        for (i, p) in points.enumerated() {
            let c = CGPoint(x: p.x * size.width, y: p.y * size.height)
            let pulse = 0.5 + 0.5 * sin(t * (0.9 + Double(i % 5) * 0.23) * layer.speed + Double(i) * 1.7)
            let r = p.r * unit * (1.15 + 0.35 * pulse + e * 0.6)
            let a = layer.intensity * (0.25 + 0.35 * pulse + e * 0.3)
            glow.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.8, y: c.y - r * 1.8, width: r * 3.6, height: r * 3.6)),
                      with: .radialGradient(Gradient(colors: [tint.opacity(a), tint.opacity(a * 0.35), .clear]),
                                            center: c, startRadius: 0, endRadius: r * 1.8))
            // Raios em cruz (cintilação).
            // Cintilação: raios curtos e finos que somem nas pontas (só nas estrelas maiores).
            if r > 4 {
                let spin = t * 0.1 * layer.speed + Double(i)
                for k in 0..<4 {
                    let ang = spin + Double(k) * .pi / 2
                    let len = r * (0.7 + pulse * 0.45 + e * 0.4)
                    let tip = CGPoint(x: c.x + cos(ang) * len, y: c.y + sin(ang) * len)
                    var ray = Path()
                    ray.move(to: c)
                    ray.addLine(to: tip)
                    glow.stroke(ray, with: .linearGradient(Gradient(colors: [.white.opacity(a * 0.5), .clear]), startPoint: c, endPoint: tip),
                                lineWidth: max(0.6, r * 0.05))
                }
            }
            // Miolo pequeno, na cor da estrela, que acende no pulso.
            glow.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.18, y: c.y - r * 0.18, width: r * 0.36, height: r * 0.36)),
                      with: .radialGradient(Gradient(colors: [.white.opacity(a * 0.7), tint.opacity(a * 0.4), .clear]),
                                            center: c, startRadius: 0, endRadius: r * 0.18))
        }
    }

    /// Redemoinho: pinceladas curtas em espiral girando em volta do ponto (céu de Van Gogh).
    static func swirls(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ layer: SkinManifest.Layer) {
        let colors = palette(layer)
        var glow = ctx
        glow.blendMode = .plusLighter
        let unit = max(size.width, size.height)
        for (n, p) in layer.points.enumerated() {
            let c = CGPoint(x: p.x * size.width, y: p.y * size.height)
            let radius = p.r * unit
            let turn = t * 0.25 * layer.speed * (1 + e * 1.5) * (n % 2 == 0 ? 1 : -1)
            for arm in 0..<3 {
                for k in 0..<26 {
                    let u = Double(k) / 26
                    let ang = turn + Double(arm) * 2.1 + u * 5.2
                    let rr = radius * (0.12 + u * 0.95)
                    let a0 = CGPoint(x: c.x + cos(ang) * rr, y: c.y + sin(ang) * rr * 0.8)
                    let a1 = CGPoint(x: c.x + cos(ang + 0.22) * rr, y: c.y + sin(ang + 0.22) * rr * 0.8)
                    var stroke = Path()
                    stroke.move(to: a0)
                    stroke.addLine(to: a1)
                    let alpha = layer.intensity * (0.10 + 0.22 * (1 - u)) * (0.7 + e * 0.6)
                    glow.stroke(stroke, with: .color(colors[(k + arm) % colors.count].opacity(alpha)),
                                style: StrokeStyle(lineWidth: max(1.5, radius * 0.045), lineCap: .round))
                }
            }
        }
    }

    /// Halo que respira (lua, sol).
    static func glows(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ layer: SkinManifest.Layer) {
        let tint = color(layer.color, Color(hex: 0xFFE27A))
        var glow = ctx
        glow.blendMode = .plusLighter
        let unit = max(size.width, size.height)
        for (i, p) in layer.points.enumerated() {
            let c = CGPoint(x: p.x * size.width, y: p.y * size.height)
            let breathe = 0.5 + 0.5 * sin(t * 0.6 * layer.speed + Double(i))
            let r = p.r * unit * (1.3 + 0.25 * breathe + e * 0.5)
            let a = layer.intensity * (0.25 + 0.25 * breathe + e * 0.3)
            glow.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                      with: .radialGradient(Gradient(colors: [tint.opacity(a), tint.opacity(a * 0.4), .clear]),
                                            center: c, startRadius: r * 0.25, endRadius: r))
        }
    }

    /// Vento: pinceladas curvas correndo pela área em ondas (fluxo do céu).
    static func flow(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ layer: SkinManifest.Layer, salt: Int) {
        let colors = palette(layer)
        let count = layer.count ?? 60
        for i in 0..<count {
            let lane = Scenes.rnd(i, 400 + salt)
            let speed = (18 + Scenes.rnd(i, 401 + salt) * 30) * layer.speed * (1 + e * 1.4)
            let span = size.width + 120
            let x = (Scenes.rnd(i, 402 + salt) * span + t * speed).truncatingRemainder(dividingBy: span) - 60
            let baseY = lane * size.height * 0.62
            let y = baseY + sin(x / size.width * 6 + lane * 9 + t * 0.4) * size.height * 0.03
            let len = 14 + Scenes.rnd(i, 403 + salt) * 26
            var stroke = Path()
            stroke.move(to: CGPoint(x: x, y: y))
            stroke.addQuadCurve(to: CGPoint(x: x + len, y: y + sin(lane * 7) * 4),
                                control: CGPoint(x: x + len / 2, y: y - 5))
            let fade = min(1, min(x + 60, span - 60 - x) / 80)
            let alpha = layer.intensity * (0.18 + Scenes.rnd(i, 404 + salt) * 0.25) * max(0, fade)
            ctx.stroke(stroke, with: .color(colors[i % colors.count].opacity(alpha)),
                       style: StrokeStyle(lineWidth: 2 + Scenes.rnd(i, 405 + salt) * 2.5, lineCap: .round))
        }
    }

    /// Imagem do skin (personagem, ornamento) com movimento.
    static func image(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ e: Double, _ layer: SkinManifest.Layer, _ img: NSImage?) {
        guard let img, let p = layer.points.first else { return }
        let w = p.r * size.width * 2
        let h = w * img.size.height / max(img.size.width, 1)
        var c = CGPoint(x: p.x * size.width, y: p.y * size.height)
        var scale = 1.0, angle = 0.0
        switch layer.motion {
        case "float": c.y += sin(t * layer.speed) * h * 0.06
        case "spin": angle = t * 0.3 * layer.speed
        case "pulse": scale = 1 + 0.06 * sin(t * 2 * layer.speed) + e * 0.12
        default: break
        }
        var copy = ctx
        copy.translateBy(x: c.x, y: c.y)
        copy.rotate(by: .radians(angle))
        copy.scaleBy(x: scale, y: scale)
        copy.opacity = layer.intensity
        copy.draw(Image(nsImage: img), in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    }
}
