import Foundation

/// Comparação tolerante de textos de tags (acentos, caixa, pontuação, "feat.").
public enum TextMatch {
    public static func normalize(_ s: String) -> String {
        var t = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        for marker in [" feat. ", " feat ", " ft. ", " featuring "] {
            if let r = t.range(of: marker) { t = String(t[..<r.lowerBound]) }
        }
        t = t.replacingOccurrences(of: "&", with: " and ")
        let kept = t.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Título sem anotações de edição: "(Remastered 2011)", "[Live]", " - 2011 Remaster", "(feat. X)".
    public static func cleanTitle(_ s: String) -> String {
        let words = "remaster|remastered|live|ao vivo|mono|stereo|version|versão|edit|mix|deluxe|bonus|feat|ft\\.|demo|acoustic|explicit"
        var t = s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*(\#(words))[^\)\]]*[\)\]]"#, with: "",
                                       options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+-\s+[^-]*(\#(words))[^-]*$"#, with: "",
                                   options: [.regularExpression, .caseInsensitive])
        let out = t.trimmingCharacters(in: .whitespaces)
        return out.isEmpty ? s : out
    }

    /// 0...1 (1 = iguais depois de normalizar).
    public static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(normalize(a)), y = Array(normalize(b))
        if x.isEmpty || y.isEmpty { return x.isEmpty && y.isEmpty ? 1 : 0 }
        if x == y { return 1 }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    /// Confiança de um resultado contra o que se sabe da faixa.
    public static func confidence(title: String, artist: String, duration: Double?,
                                  candidateTitle: String, candidateArtist: String, candidateDuration: Double?,
                                  album: String? = nil, candidateAlbum: String? = nil) -> Double {
        var score = 0.0, weight = 0.0
        if !title.isEmpty { score += 0.45 * similarity(title, candidateTitle); weight += 0.45 }
        if !artist.isEmpty { score += 0.35 * similarity(artist, candidateArtist); weight += 0.35 }
        if let d = duration, d > 0 {
            // Resultado sem duração não pode levar vantagem sobre um que tem: conta metade.
            if let c = candidateDuration, c > 0 {
                let diff = abs(d - c)
                score += 0.2 * (diff <= 2 ? 1 : diff >= 15 ? 0 : 1 - (diff - 2) / 13)
            } else {
                score += 0.1
            }
            weight += 0.2
        }
        if let a = album, !a.isEmpty, let c = candidateAlbum {
            score += 0.1 * similarity(a, c); weight += 0.1
        }
        return weight == 0 ? 0 : min(1, score / weight)
    }
}

/// Palpite de artista/título/faixa a partir do nome do arquivo ("01 - Artista - Título.mp3").
public struct FilenameGuess: Sendable, Equatable {
    public var artist: String?
    public var title: String
    public var trackNumber: Int?

    public static func parse(_ url: URL) -> FilenameGuess {
        var name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        var track: Int?
        let digits = name.prefix { $0.isNumber }
        if (1...3).contains(digits.count), let n = Int(digits) {
            let rest = name.dropFirst(digits.count)
            if rest.isEmpty || rest.first == " " || rest.first == "." || rest.first == "-" {
                track = n
                name = String(rest).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
            }
        }
        let parts = name.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return FilenameGuess(artist: parts[0], title: parts.dropFirst().joined(separator: " - "), trackNumber: track)
        }
        return FilenameGuess(artist: nil, title: name, trackNumber: track)
    }
}
