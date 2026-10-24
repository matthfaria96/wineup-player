import Foundation

/// Ajuste de tempo de letras .lrc: deslocar todas as marcas de uma vez.
public enum LyricsTiming {
    /// Desloca todas as marcas [mm:ss.xx] do texto (positivo = a letra aparece mais tarde).
    /// Tags de cabeçalho ([ar:], [offset:]...) e o resto do texto ficam como estão; nenhuma marca fica negativa.
    public static func shift(_ text: String, by seconds: Double) -> String {
        guard seconds != 0 else { return text }
        return text.components(separatedBy: "\n").map { shiftLine($0, seconds) }.joined(separator: "\n")
    }

    private static func shiftLine(_ line: String, _ seconds: Double) -> String {
        var out = ""
        var rest = Substring(line)
        // Só as marcas no começo da linha (várias seguidas são permitidas no .lrc).
        let leading = rest.prefix { $0 == " " || $0 == "\t" }
        out += leading
        rest = rest.dropFirst(leading.count)
        while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            let tag = rest[rest.index(after: rest.startIndex)..<close]
            if let t = LRCParser.time(of: tag) {
                out += "[" + format(max(0, t + seconds)) + "]"
            } else {
                out += rest[...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    /// "mm:ss.xx" (centésimos), o formato mais comum do .lrc.
    public static func format(_ seconds: Double) -> String {
        let cs = Int((seconds * 100).rounded())
        return String(format: "%02d:%02d.%02d", cs / 6000, cs / 100 % 60, cs % 100)
    }
}
