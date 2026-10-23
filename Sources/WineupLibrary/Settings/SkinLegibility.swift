import CoreGraphics
import Foundation
import ImageIO

/// Confere se o texto fica legível sobre o fundo de cada painel e corrige escurecendo a imagem.
public enum SkinLegibility {
    /// Contraste mínimo do texto sobre o fundo (WCAG AA para texto comum).
    public static let minimum = 4.5

    public struct Issue: Equatable, Sendable {
        public var panel: String
        public var contrast: Double
    }

    /// Cor média de uma imagem do skin (cacheada por caminho).
    nonisolated(unsafe) private static var averages: [String: SkinGenerator.RGB] = [:]
    private static let lock = NSLock()

    static func average(_ url: URL) -> SkinGenerator.RGB? {
        lock.lock(); defer { lock.unlock() }
        if let hit = averages[url.path] { return hit }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                     kCGImageSourceThumbnailMaxPixelSize: 96] as CFDictionary)
        else { return nil }
        let avg = SkinGenerator.palette(of: img).average
        averages[url.path] = avg
        return avg
    }

    static func rgb(_ hex: String?) -> SkinGenerator.RGB? {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count >= 6, let v = UInt64(s.prefix(6), radix: 16) else { return nil }
        return .init(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    /// Fundo efetivo do painel: média da imagem coberta pelo preto de "escurecer".
    static func background(_ fill: SkinManifest.Fill, folder: URL) -> SkinGenerator.RGB? {
        average(folder.appendingPathComponent(fill.image)).map { $0.scaled(1 - fill.dim) }
    }

    /// Painéis com texto pouco legível.
    public static func issues(_ m: SkinManifest, folder: URL) -> [Issue] {
        let text = rgb(m.colors["text"]) ?? rgb(SkinManifest.fallbackColors["text"])!
        return m.panels.keys.sorted().compactMap { key in
            guard let fill = m.panels[key]?.fill, let bg = background(fill, folder: folder) else { return nil }
            let c = SkinGenerator.contrast(text, bg)
            return c < minimum ? Issue(panel: key, contrast: c) : nil
        }
    }

    /// Escurece cada painel só o necessário para o texto chegar ao contraste mínimo.
    public static func autoFix(_ m: SkinManifest, folder: URL) -> SkinManifest {
        var out = m
        let text = rgb(m.colors["text"]) ?? rgb(SkinManifest.fallbackColors["text"])!
        for key in m.panels.keys {
            guard var fill = out.panels[key]?.fill else { continue }
            while fill.dim < 0.92, let bg = background(fill, folder: folder), SkinGenerator.contrast(text, bg) < minimum + 0.3 {
                fill.dim = min(0.92, fill.dim + 0.04)
            }
            out.panels[key]?.fill = fill
        }
        return out
    }
}
