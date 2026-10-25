import AppKit
import Foundation

// Vitrine (wineup-demo --showcase <pasta>): biblioteca fictícia para as capturas do site.
// Lançamentos inventados, faixas de 3 a 4 minutos, capas desenhadas aqui e letras sincronizadas (.lrc).

/// Ligado pelo argumento --showcase: troca o catálogo, as capas e grava as letras .lrc.
nonisolated(unsafe) var showcaseMode = false

let showcaseCatalog: [DemoTrack] = {
    func t(_ title: String, _ artist: String, _ album: String?, _ genre: String?, _ n: Int, _ year: String,
           _ seconds: Double, _ root: Double, _ tempo: Double, _ format: String) -> DemoTrack {
        DemoTrack(title: title, artist: artist, album: album, genre: genre, number: n, year: year, seconds: seconds,
                  root: root, tempo: tempo, format: format, lyrics: nil)
    }
    return [
        t("Abertura do Vinho", "Os Taninos", "Noites de Vinho", "Rock", 1, "2024", 214, 220, 112, "flac"),
        t("Safra Antiga", "Os Taninos", "Noites de Vinho", "Rock", 2, "2024", 187, 196, 96, "flac"),
        t("Rolha Solta", "Os Taninos", "Noites de Vinho", "Rock", 3, "2024", 168, 247, 128, "flac"),
        t("Decantar", "Os Taninos", "Noites de Vinho", "Rock", 4, "2024", 236, 174.6, 88, "m4a"),
        t("Última Taça", "Os Taninos", "Noites de Vinho", "Rock", 5, "2024", 245, 207.7, 100, "m4a"),
        t("Ondas Curtas", "Maré Sintética", "Frequências", "Eletrônica", 1, "2023", 222, 261.6, 124, "m4a"),
        t("Estática Azul", "Maré Sintética", "Frequências", "Eletrônica", 2, "2023", 199, 293.7, 120, "flac"),
        t("Sinal Fraco", "Maré Sintética", "Frequências", "Eletrônica", 3, "2023", 183, 329.6, 132, "flac"),
        t("Fim de Transmissão", "Maré Sintética", "Frequências", "Eletrônica", 4, "2023", 251, 246.9, 110, "m4a"),
        t("Céu de Neon", "Luna Vale", "Céu de Neon", "Synthpop", 1, "2025", 203, 277.2, 118, "m4a"),
        t("Avenida 80", "Luna Vale", "Céu de Neon", "Synthpop", 2, "2025", 191, 311.1, 122, "m4a"),
        t("Chuva Ácida", "Luna Vale", "Céu de Neon", "Synthpop", 3, "2025", 228, 233.1, 104, "flac"),
        t("Holograma", "Luna Vale", "Céu de Neon", "Synthpop", 4, "2025", 176, 349.2, 126, "m4a"),
        t("Varanda", "Bento Grave", "Varanda", "MPB", 1, "2022", 207, 196, 84, "flac"),
        t("Ladeira", "Bento Grave", "Varanda", "MPB", 2, "2022", 194, 233.1, 92, "flac"),
        t("Rede ao Sol", "Bento Grave", "Varanda", "MPB", 3, "2022", 219, 220, 78, "m4a"),
        t("Ruído Branco", "Os Fósforos", "Ruído Branco", "Indie", 1, "2024", 172, 246.9, 138, "flac"),
        t("Faísca", "Os Fósforos", "Ruído Branco", "Indie", 2, "2024", 158, 293.7, 144, "flac"),
        t("Pavio Curto", "Os Fósforos", "Ruído Branco", "Indie", 3, "2024", 181, 261.6, 132, "m4a"),
        t("Café às Três", "Lia Sol", nil, "Pop", 1, "2025", 196, 349.2, 104, "m4a"),
        t("Demo Sem Nome", "Desconhecido do Porão", nil, nil, 1, "2021", 142, 277.2, 116, "flac"),
    ]
}()

/// Letras sincronizadas por título (uma linha a cada ~4 s, a partir de 2 s).
let showcaseLyrics: [String: [String]] = [
    "Última Taça": ["Última taça da noite", "O disco gira sem fim", "Guardo o som do teu riso",
                    "Tocando dentro de mim", "A rua já está vazia", "Só o neon ficou aceso",
                    "Mais uma volta na agulha", "E o tempo fica preso", "Brinda comigo de novo",
                    "Que a manhã pode esperar", "Última taça da noite", "Ninguém quer ir pra casa"],
    "Céu de Neon": ["Luzes rosas na janela", "A cidade aprende a brilhar", "Teu nome numa vitrine",
                    "Piscando sem parar", "Céu de neon, me leva", "Pra onde a noite não tem fim",
                    "Céu de neon, acende", "Tudo que existe em mim", "Carros cortam a avenida",
                    "Como cometas no chão", "Céu de neon, me leva", "Dentro dessa canção"],
    "Café às Três": ["Café às três da manhã", "A cidade dorme em paz", "Uma canção no rádio",
                     "E nada mais", "A xícara ainda quente", "O vapor desenha o ar",
                     "Tem uma estrela teimosa", "Que não quer se apagar", "Café às três da manhã",
                     "Eu e o som do vinil", "Café às três da manhã", "O mundo inteiro sumiu"],
    "Varanda": ["Rede balança devagar", "O sol desce no quintal", "Um violão na varanda",
                "Toca um samba sem final", "Cheiro de terra molhada", "Chuva fina no telhado",
                "A tarde vira poesia", "Com você aqui do lado"],
]

/// Grava o .lrc ao lado da música (o Wineup lê a letra sincronizada dele).
func writeShowcaseLyrics(for t: DemoTrack, audio: URL) throws {
    guard showcaseMode, let lines = showcaseLyrics[t.title] else { return }
    var text = "[ar:\(t.artist)]\n[ti:\(t.title)]\n"
    for (i, line) in lines.enumerated() {
        let time = 2.0 + Double(i) * 4.2
        text += String(format: "[%02d:%05.2f]%@\n", Int(time) / 60, time.truncatingRemainder(dividingBy: 60), line)
    }
    try text.write(to: audio.deletingPathExtension().appendingPathExtension("lrc"), atomically: true, encoding: .utf8)
}

// MARK: - Capas

/// Capa desenhada para cada lançamento da vitrine (1000×1000).
func showcaseCover(for t: DemoTrack) -> Data? {
    guard showcaseMode else { return nil }
    let key = t.album ?? t.title
    return render(1000) { ctx, s in
        switch key {
        case "Noites de Vinho": wine(ctx, s)
        case "Frequências": synthSun(ctx, s)
        case "Céu de Neon": neonBlobs(ctx, s)
        case "Varanda": varanda(ctx, s)
        case "Ruído Branco": stripes(ctx, s)
        case "Café às Três": dots(ctx, s)
        default: tape(ctx, s)
        }
        label(key, by: t.artist, in: s, dark: key == "Varanda")
    }
}

private func render(_ size: Int, _ draw: (CGContext, CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    draw(g.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
}

private func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

private func linear(_ ctx: CGContext, _ s: CGFloat, _ colors: [NSColor], angle: CGFloat) {
    NSGradient(colors: colors)!.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: angle)
}

private func radial(_ ctx: CGContext, center: CGPoint, radius: CGFloat, _ color: NSColor) {
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Vinho: degradê bordô, taça estilizada em anéis e brilho dourado.
private func wine(_ ctx: CGContext, _ s: CGFloat) {
    linear(ctx, s, [rgb(0x2A0712), rgb(0x6E1023), rgb(0x1A050B)], angle: -70)
    radial(ctx, center: CGPoint(x: s * 0.72, y: s * 0.7), radius: s * 0.55, rgb(0xE8742A, 0.35))
    for k in 0..<9 {
        let r = s * (0.18 + CGFloat(k) * 0.07)
        ctx.setStrokeColor(rgb(0xF5C16C, 0.10 + CGFloat(8 - k) * 0.012).cgColor)
        ctx.setLineWidth(s * 0.006)
        ctx.strokeEllipse(in: CGRect(x: s * 0.62 - r / 2, y: s * 0.62 - r / 2, width: r, height: r))
    }
    ctx.setFillColor(rgb(0xF5C16C, 0.9).cgColor)
    ctx.fillEllipse(in: CGRect(x: s * 0.60, y: s * 0.60, width: s * 0.04, height: s * 0.04))
}

/// Sol synthwave sobre grade em perspectiva.
private func synthSun(_ ctx: CGContext, _ s: CGFloat) {
    linear(ctx, s, [rgb(0x0B0631), rgb(0x3B0A57), rgb(0xFF3D7F)], angle: 90)
    let sun = CGRect(x: s * 0.25, y: s * 0.38, width: s * 0.5, height: s * 0.5)
    ctx.saveGState()
    ctx.addEllipse(in: sun)
    ctx.clip()
    NSGradient(colors: [rgb(0xFF2E88), rgb(0xFFB347), rgb(0xFFF07A)])!.draw(in: sun, angle: 90)
    ctx.setFillColor(rgb(0x2A0845).cgColor)
    for k in 0..<6 {
        let h = s * (0.008 + CGFloat(k) * 0.006)
        ctx.fill(CGRect(x: sun.minX, y: sun.minY + s * 0.04 + CGFloat(k) * s * 0.05, width: sun.width, height: h))
    }
    ctx.restoreGState()
    ctx.setFillColor(rgb(0x12052B).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s * 0.4))
    ctx.setStrokeColor(rgb(0xFF3DF0, 0.75).cgColor)
    ctx.setLineWidth(s * 0.004)
    for k in 0..<10 {
        let y = s * 0.4 * pow(CGFloat(k) / 10, 1.8)
        ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: s, y: y))
    }
    for k in -8...8 {
        ctx.move(to: CGPoint(x: s / 2 + CGFloat(k) * s * 0.02, y: s * 0.4))
        ctx.addLine(to: CGPoint(x: s / 2 + CGFloat(k) * s * 0.16, y: 0))
    }
    ctx.strokePath()
}

/// Bolhas de luz rosa, azul e violeta desfocadas.
private func neonBlobs(_ ctx: CGContext, _ s: CGFloat) {
    linear(ctx, s, [rgb(0x0A0F2C), rgb(0x1B0B3A)], angle: -45)
    radial(ctx, center: CGPoint(x: s * 0.25, y: s * 0.7), radius: s * 0.55, rgb(0xFF2D95, 0.85))
    radial(ctx, center: CGPoint(x: s * 0.8, y: s * 0.55), radius: s * 0.5, rgb(0x2DE2FF, 0.7))
    radial(ctx, center: CGPoint(x: s * 0.55, y: s * 0.2), radius: s * 0.45, rgb(0x8B5CF6, 0.75))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    ctx.setLineWidth(s * 0.01)
    ctx.strokeEllipse(in: CGRect(x: s * 0.36, y: s * 0.36, width: s * 0.28, height: s * 0.28))
}

/// Papel claro com sol laranja e linhas de rede: MPB de fim de tarde.
private func varanda(_ ctx: CGContext, _ s: CGFloat) {
    linear(ctx, s, [rgb(0xF3E7D3), rgb(0xE9D6B9)], angle: 90)
    ctx.setFillColor(rgb(0xE8742A).cgColor)
    ctx.fillEllipse(in: CGRect(x: s * 0.52, y: s * 0.5, width: s * 0.3, height: s * 0.3))
    ctx.setStrokeColor(rgb(0x2F5D50).cgColor)
    ctx.setLineWidth(s * 0.008)
    for k in 0..<7 {
        let x = s * 0.12 + CGFloat(k) * s * 0.11
        ctx.move(to: CGPoint(x: x, y: s * 0.62))
        ctx.addQuadCurve(to: CGPoint(x: x + s * 0.11, y: s * 0.62), control: CGPoint(x: x + s * 0.055, y: s * 0.44))
    }
    ctx.strokePath()
    ctx.setFillColor(rgb(0x2F5D50).cgColor)
    ctx.fill(CGRect(x: 0, y: s * 0.30, width: s, height: s * 0.012))
}

/// Faixas diagonais em preto, branco e vermelho.
private func stripes(_ ctx: CGContext, _ s: CGFloat) {
    rgb(0x111111).setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()
    let colors = [rgb(0xF2F2F2), rgb(0xE5322D), rgb(0x111111), rgb(0xF2F2F2), rgb(0x111111)]
    for k in -6..<12 {
        ctx.saveGState()
        ctx.translateBy(x: s / 2, y: s / 2)
        ctx.rotate(by: -.pi / 5)
        colors[(k + 12) % colors.count].setFill()
        NSRect(x: -s, y: CGFloat(k) * s * 0.09 - s / 2, width: s * 2, height: s * 0.05).fill()
        ctx.restoreGState()
    }
}

/// Retícula de pontos em amarelo e laranja (pop).
private func dots(_ ctx: CGContext, _ s: CGFloat) {
    linear(ctx, s, [rgb(0xFFD23F), rgb(0xFF8C42)], angle: -60)
    for row in 0..<14 {
        for col in 0..<14 {
            let x = s * (CGFloat(col) + 0.5) / 14, y = s * (CGFloat(row) + 0.5) / 14
            let d = hypot(x - s * 0.3, y - s * 0.75) / s
            let r = s * 0.03 * max(0.15, 1.2 - d * 1.5)
            ctx.setFillColor(rgb(0x7A1F3D, 0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }
}

/// Fita cassete escura com etiqueta (demo sem álbum).
private func tape(_ ctx: CGContext, _ s: CGFloat) {
    linear(ctx, s, [rgb(0x23262E), rgb(0x0E0F13)], angle: -90)
    let body = CGRect(x: s * 0.14, y: s * 0.36, width: s * 0.72, height: s * 0.44)
    ctx.setFillColor(rgb(0x3A3F4B).cgColor)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: s * 0.03, cornerHeight: s * 0.03, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(rgb(0xEDE6D6).cgColor)
    ctx.fill(CGRect(x: body.minX + s * 0.05, y: body.midY, width: body.width - s * 0.1, height: s * 0.14))
    ctx.setFillColor(rgb(0x14161B).cgColor)
    for x in [0.36, 0.64] {
        ctx.fillEllipse(in: CGRect(x: s * CGFloat(x) - s * 0.05, y: body.minY + s * 0.06, width: s * 0.1, height: s * 0.1))
    }
}

/// Título e artista no pé da capa.
private func label(_ title: String, by artist: String, in s: CGFloat, dark: Bool) {
    let ink = dark ? rgb(0x1F2A26) : NSColor.white
    NSString(string: title.uppercased()).draw(at: NSPoint(x: s * 0.07, y: s * 0.12), withAttributes: [
        .font: NSFont.systemFont(ofSize: s * 0.068, weight: .black), .foregroundColor: ink, .kern: s * 0.002])
    NSString(string: artist).draw(at: NSPoint(x: s * 0.075, y: s * 0.075), withAttributes: [
        .font: NSFont.systemFont(ofSize: s * 0.032, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.8)])
}
