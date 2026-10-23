import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Cria um skin completo a partir de uma imagem: fundo, recortes dos painéis, cores tiradas da
/// própria imagem (com contraste garantido) e moldura/botões/puxador/campo num estilo pronto.
public enum SkinGenerator {
    public enum Style: String, CaseIterable, Sendable, Identifiable {
        case gold, metal, neon, minimal

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .gold: "Dourado (museu)"
            case .metal: "Metal escovado"
            case .neon: "Neon"
            case .minimal: "Minimalista"
            }
        }
    }

    public struct RGB: Equatable, Sendable {
        public var r: Double, g: Double, b: Double
        public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

        public var hex: String {
            String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        }
        func hex(alpha: Double) -> String { hex + String(format: "%02X", Int((alpha * 255).rounded())) }

        /// Luminância relativa (WCAG).
        public var luminance: Double {
            func ch(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
        }
        var saturation: Double { let mx = max(r, g, b), mn = min(r, g, b); return mx == 0 ? 0 : (mx - mn) / mx }
        func mixed(_ o: RGB, _ t: Double) -> RGB { RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t) }
        func scaled(_ k: Double) -> RGB { RGB(min(1, r * k), min(1, g * k), min(1, b * k)) }
        var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        func cg(_ a: Double) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    }

    /// Contraste WCAG entre duas cores (1...21).
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let l1 = max(a.luminance, b.luminance), l2 = min(a.luminance, b.luminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }

    // MARK: Paleta

    public struct Palette: Equatable, Sendable {
        public var average: RGB
        public var dark: RGB
        public var accent: RGB
    }

    /// Média, tom escuro dominante e cor de destaque (a mais saturada e clara presente em boa quantidade).
    public static func palette(of image: CGImage) -> Palette {
        let n = 48
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var all: [RGB] = []
        for i in 0..<(n * n) { all.append(RGB(Double(px[i * 4]) / 255, Double(px[i * 4 + 1]) / 255, Double(px[i * 4 + 2]) / 255)) }
        let avg = all.reduce(RGB(0, 0, 0)) { RGB($0.r + $1.r, $0.g + $1.g, $0.b + $1.b) }
        let average = RGB(avg.r / Double(all.count), avg.g / Double(all.count), avg.b / Double(all.count))
        let darkest = all.sorted { $0.luminance < $1.luminance }.prefix(all.count / 4)
        let d = darkest.reduce(RGB(0, 0, 0)) { RGB($0.r + $1.r, $0.g + $1.g, $0.b + $1.b) }
        var dark = RGB(d.r / Double(darkest.count), d.g / Double(darkest.count), d.b / Double(darkest.count))
        if dark.luminance > 0.04 { dark = dark.scaled(0.45) }
        // Destaque: pontua saturação × brilho, em baldes de matiz para pegar uma cor que existe de fato.
        let candidates = all.filter { $0.saturation > 0.35 && max($0.r, $0.g, $0.b) > 0.45 }
        var accent = candidates.max { $0.saturation * max($0.r, $0.g, $0.b) < $1.saturation * max($1.r, $1.g, $1.b) }
            ?? RGB(0.95, 0.78, 0.30)
        if max(accent.r, accent.g, accent.b) < 0.75 { accent = accent.scaled(0.85 / max(accent.r, accent.g, accent.b)) }
        return Palette(average: average, dark: dark, accent: accent)
    }

    // MARK: Gerar

    /// Cria a pasta do skin (skin.json + arte) em `folder` a partir da imagem.
    @discardableResult
    public static func generate(from imageURL: URL, name: String, id: String, style: Style, author: String,
                                into folder: URL) throws -> SkinManifest {
        guard let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pal = palette(of: image)
        let W = Double(image.width), H = Double(image.height)

        func save(_ img: CGImage, _ file: String, jpeg: Bool) throws {
            let url = folder.appendingPathComponent(file)
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, (jpeg ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil)
            else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(dest, img, jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary : nil)
            guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        }
        func crop(_ x: Double, _ y: Double, _ w: Double, _ h: Double, width: Int) -> CGImage {
            let rect = CGRect(x: x * W, y: y * H, width: w * W, height: h * H).integral
            let piece = image.cropping(to: rect) ?? image
            let height = max(1, Int(Double(width) * rect.height / max(rect.width, 1)))
            let ctx = context(width, height)
            ctx.interpolationQuality = .high
            ctx.draw(piece, in: CGRect(x: 0, y: 0, width: width, height: height))
            return ctx.makeImage()!
        }

        try save(crop(0, 0, 1, 1, width: min(2400, image.width)), "background.jpg", jpeg: true)
        try save(crop(0.2, 0.0, 0.6, 0.5, width: 1200), "panel-top.jpg", jpeg: true)
        try save(crop(0.0, 0.3, 0.45, 0.7, width: 1000), "panel-left.jpg", jpeg: true)
        try save(crop(0.55, 0.3, 0.45, 0.7, width: 1000), "panel-right.jpg", jpeg: true)
        try save(crop(0.25, 0.5, 0.5, 0.5, width: 1000), "panel-bottom.jpg", jpeg: true)
        try save(drawFrame(style, pal), "frame.png", jpeg: false)
        try save(drawButton(style, pal, on: false), "button.png", jpeg: false)
        try save(drawButton(style, pal, on: true), "button-on.png", jpeg: false)
        try save(drawKnob(style, pal), "knob.png", jpeg: false)
        try save(drawField(style, pal), "field.png", jpeg: false)

        var m = SkinManifest(id: id, name: name)
        m.author = author
        m.description = "Criado a partir de \(imageURL.lastPathComponent), estilo \(style.title.lowercased())."
        m.colors = colors(pal, style: style)
        m.window.background = .init(image: "background.jpg", dim: 0.2)
        m.window.layers = [.init(kind: .flow, name: "brilho", colors: [pal.accent.hex, "#FFFFFF"], speed: 0.6, intensity: 0.25, count: 30)]
        let frame = SkinManifest.NineSlice(image: "frame.png", slice: 48, width: 12)
        let dim = 0.62
        m.panels = [
            "default": .init(fill: .init(image: "panel-top.jpg", dim: dim), frame: frame, cornerRadius: 12),
            "playlist": .init(fill: .init(image: "panel-left.jpg", dim: dim + 0.08), frame: frame, cornerRadius: 12),
            "equalizer": .init(fill: .init(image: "panel-right.jpg", dim: dim), frame: frame, cornerRadius: 12),
            "artwork": .init(fill: .init(image: "panel-bottom.jpg", dim: dim - 0.1), frame: frame, cornerRadius: 12),
            "lyrics": .init(fill: .init(image: "panel-right.jpg", dim: dim + 0.1), frame: frame, cornerRadius: 12),
        ]
        m.controls.button = .init(image: "button.png", slice: 14, width: 7)
        m.controls.buttonOn = .init(image: "button-on.png", slice: 14, width: 7)
        m.controls.field = .init(image: "field.png", slice: 14, width: 7)
        m.controls.knob = "knob.png"
        m.controls.knobSize = 20
        m.display.glow = style == .neon ? 0.9 : 0.5
        try SkinStore.encode(m).write(to: folder.appendingPathComponent("skin.json"), options: .atomic)
        return m
    }

    /// Cores do skin: escuros da imagem no fundo, destaque da imagem, texto claro com contraste ≥ 7:1 no painel.
    static func colors(_ p: Palette, style: Style) -> [String: String] {
        let panel = p.dark.mixed(RGB(0, 0, 0), 0.3)
        var text = RGB(0.98, 0.97, 0.94)
        if contrast(text, panel) < 7 { text = RGB(1, 1, 1) }
        let muted = text.mixed(p.average, 0.35)
        let accent = p.accent
        let onAccent = contrast(RGB(0.08, 0.06, 0.04), accent) > contrast(RGB(1, 1, 1), accent) ? RGB(0.08, 0.06, 0.04) : RGB(1, 1, 1)
        return [
            "windowTop": p.dark.mixed(p.average, 0.25).hex, "windowBottom": p.dark.hex, "panelFill": panel.hex(alpha: 0.8),
            "panelBorder": accent.hex(alpha: 0.6), "text": text.hex, "mutedText": muted.hex, "accent": accent.hex,
            "rowSelection": accent.hex(alpha: 0.22), "currentRow": accent.hex, "lyricsActive": accent.mixed(RGB(1, 1, 1), 0.3).hex,
            "lyricsIdle": text.hex(alpha: 0.8), "control": accent.hex, "artworkTint": p.dark.mixed(p.average, 0.4).hex,
            "display": accent.mixed(RGB(1, 1, 1), 0.2).hex, "buttonText": text.hex, "buttonTextOn": onAccent.hex,
        ]
    }

    // MARK: Arte dos controles (por estilo)

    static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func metalColors(_ style: Style, _ p: Palette) -> [CGColor] {
        switch style {
        case .gold:
            return [RGB(1, 0.95, 0.75).cg, RGB(0.91, 0.76, 0.35).cg, RGB(0.72, 0.53, 0.16).cg, RGB(0.88, 0.70, 0.29).cg, RGB(0.48, 0.32, 0.06).cg]
        case .metal:
            return [RGB(0.95, 0.96, 0.98).cg, RGB(0.72, 0.74, 0.78).cg, RGB(0.45, 0.47, 0.52).cg, RGB(0.70, 0.72, 0.76).cg, RGB(0.25, 0.26, 0.30).cg]
        case .neon, .minimal:
            let a = p.accent
            return [a.mixed(RGB(1, 1, 1), 0.5).cg, a.cg, a.scaled(0.7).cg, a.cg, a.scaled(0.45).cg]
        }
    }

    /// Moldura de 9 fatias com cantos arredondados (canto 48 de 160 px).
    static func drawFrame(_ style: Style, _ p: Palette) -> CGImage {
        let s = 160, ctx = context(s, s)
        let full = CGRect(x: 1, y: 1, width: CGFloat(s) - 2, height: CGFloat(s) - 2)
        let ring: CGFloat = style == .minimal ? 8 : (style == .neon ? 14 : 24)
        let outerR: CGFloat = 46, innerR = max(outerR - ring, 6)
        let outer = CGPath(roundedRect: full, cornerWidth: outerR, cornerHeight: outerR, transform: nil)
        let inner = full.insetBy(dx: ring, dy: ring)
        let hole = CGPath(roundedRect: inner, cornerWidth: innerR, cornerHeight: innerR, transform: nil)
        let band = CGMutablePath(); band.addPath(outer); band.addPath(hole)
        if style == .neon {
            // Tubo de luz: brilho largo e núcleo claro.
            let mid = CGPath(roundedRect: full.insetBy(dx: ring / 2, dy: ring / 2), cornerWidth: outerR - ring / 2,
                             cornerHeight: outerR - ring / 2, transform: nil)
            for (w, a) in [(12.0, 0.18), (7.0, 0.35), (3.5, 0.9)] {
                ctx.addPath(mid); ctx.setStrokeColor(p.accent.cg(a)); ctx.setLineWidth(w); ctx.strokePath()
            }
            ctx.addPath(mid); ctx.setStrokeColor(p.accent.mixed(RGB(1, 1, 1), 0.7).cg); ctx.setLineWidth(1.2); ctx.strokePath()
            return ctx.makeImage()!
        }
        ctx.saveGState(); ctx.addPath(band); ctx.clip(using: .evenOdd)
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: metalColors(style, p) as CFArray,
                              locations: [0, 0.25, 0.55, 0.8, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(s)), end: .zero, options: [])
        if style == .metal {
            // Escovado: riscos horizontais finos.
            for y in stride(from: 0, to: s, by: 2) {
                ctx.setStrokeColor(CGColor(gray: y % 4 == 0 ? 1 : 0, alpha: 0.06)); ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: 0, y: CGFloat(y))); ctx.addLine(to: CGPoint(x: CGFloat(s), y: CGFloat(y))); ctx.strokePath()
            }
        }
        if style == .gold {
            let mid = full.insetBy(dx: ring / 2, dy: ring / 2)
            let midPath = CGPath(roundedRect: mid, cornerWidth: outerR - ring / 2, cornerHeight: outerR - ring / 2, transform: nil)
            ctx.addPath(midPath); ctx.setStrokeColor(RGB(0.42, 0.29, 0.07).cg(0.55)); ctx.setLineWidth(5); ctx.strokePath()
            ctx.addPath(midPath); ctx.setStrokeColor(RGB(1, 0.96, 0.81).cg(0.75)); ctx.setLineWidth(1.2); ctx.strokePath()
            for k in stride(from: 52, through: s - 52, by: 9) {
                for pt in [CGPoint(x: CGFloat(k), y: mid.minY), CGPoint(x: CGFloat(k), y: mid.maxY),
                           CGPoint(x: mid.minX, y: CGFloat(k)), CGPoint(x: mid.maxX, y: CGFloat(k))] {
                    ctx.setFillColor(RGB(1, 0.91, 0.63).cg); ctx.fillEllipse(in: CGRect(x: pt.x - 2.4, y: pt.y - 2.4, width: 4.8, height: 4.8))
                }
            }
        }
        ctx.restoreGState()
        ctx.addPath(outer); ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.8)); ctx.setLineWidth(2); ctx.strokePath()
        ctx.addPath(hole); ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.8)); ctx.setLineWidth(2); ctx.strokePath()
        return ctx.makeImage()!
    }

    /// Botão (9 fatias, canto 14 de 48): normal = tom escuro com aro; ligado = cor de destaque.
    static func drawButton(_ style: Style, _ p: Palette, on: Bool) -> CGImage {
        let s = 48, ctx = context(s, s)
        let rect = CGRect(x: 3, y: 3, width: s - 6, height: s - 6)
        let path = CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil)
        let base = on ? p.accent : p.dark.mixed(p.average, 0.35)
        ctx.addPath(path); ctx.saveGState(); ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [base.mixed(RGB(1, 1, 1), 0.18).cg, base.scaled(0.8).cg] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(s)), end: .zero, options: [])
        ctx.restoreGState()
        let rim: CGColor = switch style {
        case .gold: RGB(0.91, 0.76, 0.35).cg
        case .metal: RGB(0.78, 0.80, 0.84).cg
        case .neon: p.accent.cg
        case .minimal: p.accent.cg(0.6)
        }
        if style == .neon {
            ctx.addPath(path); ctx.setStrokeColor(p.accent.cg(0.35)); ctx.setLineWidth(5); ctx.strokePath()
        }
        ctx.addPath(path); ctx.setStrokeColor(rim); ctx.setLineWidth(style == .minimal ? 1.2 : 2); ctx.strokePath()
        return ctx.makeImage()!
    }

    static func drawKnob(_ style: Style, _ p: Palette) -> CGImage {
        let s = 64, ctx = context(s, s)
        let c = CGPoint(x: 32, y: 32)
        let halo = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [p.accent.cg(0.7), p.accent.cg(0)] as CFArray, locations: [0, 1])!
        if style != .minimal { ctx.drawRadialGradient(halo, startCenter: c, startRadius: 0, endCenter: c, endRadius: 30, options: []) }
        let body = CGRect(x: 19, y: 19, width: 26, height: 26)
        let fill = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: metalColors(style, p) as CFArray,
                              locations: [0, 0.25, 0.55, 0.8, 1])!
        ctx.saveGState(); ctx.addEllipse(in: body); ctx.clip()
        ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: 45), end: CGPoint(x: 0, y: 19), options: [])
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.6)); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: body)
        return ctx.makeImage()!
    }

    static func drawField(_ style: Style, _ p: Palette) -> CGImage {
        let s = 48, ctx = context(s, s)
        let rect = CGRect(x: 2, y: 2, width: s - 4, height: s - 4)
        let path = CGPath(roundedRect: rect, cornerWidth: 9, cornerHeight: 9, transform: nil)
        ctx.addPath(path); ctx.setFillColor(p.dark.scaled(0.7).cg(0.9)); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(style == .metal ? RGB(0.78, 0.80, 0.84).cg(0.8) : p.accent.cg(0.75))
        ctx.setLineWidth(1.5); ctx.strokePath()
        return ctx.makeImage()!
    }
}

extension SkinStore {
    /// Novo skin do usuário a partir de uma imagem.
    public func createFromImage(_ image: URL, name: String, style: SkinGenerator.Style, author: String = "") throws -> Skin {
        let id = uniqueIDPublic(from: name)
        let folder = userFolder.appendingPathComponent(id, isDirectory: true)
        do {
            try SkinGenerator.generate(from: image, name: name, id: id, style: style, author: author, into: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        reload()
        guard let skin = skin(id) else { throw CocoaError(.fileReadCorruptFile) }
        return skin
    }
}
