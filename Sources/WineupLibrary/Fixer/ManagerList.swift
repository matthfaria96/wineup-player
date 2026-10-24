import Foundation

/// Posição de cada linha pelo id: busca O(1) em vez de varrer a lista a cada edição.
public struct RowIndex<ID: Hashable>: Sendable where ID: Sendable {
    private let positions: [ID: Int]

    public init<S: Sequence>(_ ids: S) where S.Element == ID {
        var map: [ID: Int] = [:]
        for (i, id) in ids.enumerated() where map[id] == nil { map[id] = i }
        positions = map
    }

    public subscript(_ id: ID) -> Int? { positions[id] }

    /// Posições dos ids pedidos, em ordem crescente (ids ausentes ficam de fora).
    public func positions<S: Sequence>(of ids: S) -> [Int] where S.Element == ID {
        ids.compactMap { positions[$0] }.sorted()
    }

    public var count: Int { positions.count }
}

/// Filtro de texto da lista: uma chave normalizada por linha, calculada quando os campos mudam.
public enum ManagerSearch {
    /// Separador que a consulta normalizada nunca contém: um termo não casa atravessando dois campos.
    static let separator = "\n"

    public static func key(_ parts: [String]) -> String {
        parts.map(TextMatch.normalize).joined(separator: separator)
    }

    /// `query` já normalizada; vazia casa com tudo.
    public static func matches(key: String, query: String) -> Bool {
        query.isEmpty || key.contains(query)
    }
}

/// Edições do gerenciador: o texto fica como digitado (espaços inclusos) e só é aparado ao gravar.
public enum ManagerEdits {
    /// Valor guardado para `field`: nil quando é igual ao do arquivo (desfaz a edição).
    public static func stored(_ value: String, original: String) -> String? {
        value == original ? nil : value
    }

    /// O que vai para o arquivo: valores aparados, sem os que ficam iguais ao original.
    public static func committed(_ edits: [String: String], original: (String) -> String) -> [String: String] {
        edits.reduce(into: [:]) { out, pair in
            let trimmed = pair.value.trimmingCharacters(in: .whitespaces)
            if trimmed != original(pair.key) { out[pair.key] = trimmed }
        }
    }
}

/// Quantas linhas têm cada problema aberto, numa passada só.
public enum IssueCounts {
    public static func count<S: Sequence>(_ issues: S) -> [FixerIssue: Int] where S.Element: Sequence, S.Element.Element == FixerIssue {
        issues.reduce(into: [:]) { out, list in
            for issue in list { out[issue, default: 0] += 1 }
        }
    }
}
