import Foundation

/// Chave de ordenação "natural" calculada uma vez por valor: minúsculas, sem acentos e com os números
/// completados com zeros (assim "Faixa 2" vem antes de "Faixa 10" numa comparação simples de texto).
/// Comparar estas chaves com `<` é muito mais barato que `localizedStandardCompare` a cada comparação.
public enum NaturalSortKey {
    static let digitWidth = 12

    public static func make(_ text: String) -> String {
        let folded = text.utf8.allSatisfy { $0 < 128 }
            ? text.lowercased()
            : text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var out = String.UnicodeScalarView()
        var digits = String.UnicodeScalarView()
        func flush() {
            guard !digits.isEmpty else { return }
            let padding = max(0, digitWidth - digits.count)
            out.append(contentsOf: String(repeating: "0", count: padding).unicodeScalars)
            out.append(contentsOf: digits)
            digits.removeAll(keepingCapacity: true)
        }
        for scalar in folded.unicodeScalars {
            if scalar.value >= 48 && scalar.value <= 57 { digits.append(scalar) } else {
                flush()
                out.append(scalar)
            }
        }
        flush()
        return String(out)
    }
}

/// Valor de uma coluna já extraído para ordenar (texto em chave natural ou número).
public enum SortValue: Comparable, Sendable {
    case number(Double)
    case text(String)

    /// Converte o valor lido por um key path (String, Int, Int64 ou Double); o resto não ordena.
    public init(any value: Any) {
        switch value {
        case let s as String: self = .text(s)
        case let i as Int: self = .number(Double(i))
        case let i as Int64: self = .number(Double(i))
        case let d as Double: self = .number(d)
        case let o as Double?: self = .number(o ?? 0)
        case let o as String?: self = .text(o ?? "")
        default: self = .number(0)
        }
    }
}

public enum ManagerSort {
    /// Posições de `keys` em ordem: `keys[i]` traz um valor por critério; `ascending[c]` diz a direção de cada um.
    /// Empates mantêm a ordem original (ordenação estável).
    public static func order(_ keys: [[SortValue]], ascending: [Bool]) -> [Int] {
        keys.indices.sorted { a, b in
            for (c, up) in ascending.enumerated() where c < keys[a].count && c < keys[b].count {
                let x = keys[a][c], y = keys[b][c]
                if x == y { continue }
                return up ? x < y : y < x
            }
            return a < b
        }
    }
}
