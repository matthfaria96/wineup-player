import Combine
import Foundation

/// Arquivo de tema (.wineuptheme): JSON aberto para editar à mão ou no editor de temas.
///
///     {
///       "format": "wineup-theme", "version": 1,
///       "id": "meu-tema", "name": "Meu tema", "author": "Eu",
///       "colors": { "windowTop": "#1E1E20", "panelBorder": "#FFFFFF1F", ... }
///     }
///
/// Cores em "#RRGGBB" ou "#RRGGBBAA". Cor que faltar usa a do Grafite.
public struct ThemeFile: Codable, Equatable, Identifiable, Sendable {
    public enum Token: String, CaseIterable, Identifiable, Sendable {
        case windowTop, windowBottom, panelFill, panelBorder, text, mutedText, accent
        case rowSelection, currentRow, lyricsActive, lyricsIdle, control, artworkTint, display

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .windowTop: "Fundo da janela (topo)"
            case .windowBottom: "Fundo da janela (base)"
            case .panelFill: "Fundo dos painéis"
            case .panelBorder: "Borda dos painéis"
            case .text: "Texto"
            case .mutedText: "Texto secundário"
            case .accent: "Destaque"
            case .rowSelection: "Linha selecionada"
            case .currentRow: "Música tocando"
            case .lyricsActive: "Letra: linha atual"
            case .lyricsIdle: "Letra: outras linhas"
            case .control: "Controles (sliders, bordas)"
            case .artworkTint: "Fundo da capa"
            case .display: "Visor (relógio LCD)"
            }
        }
    }

    public var format = "wineup-theme"
    public var version = 1
    public var id: String
    public var name: String
    public var author: String = ""
    public var colors: [String: String]

    public static let graphite = ThemeFile(id: "graphite", name: "Grafite", author: "Wineup", colors: [
        "windowTop": "#1E1E20", "windowBottom": "#141416", "panelFill": "#252527EB", "panelBorder": "#FFFFFF1F",
        "text": "#FFFFFF", "mutedText": "#9A9A9E", "accent": "#E5322D", "rowSelection": "#FFFFFF24",
        "currentRow": "#FF3B30", "lyricsActive": "#FFFFFF", "lyricsIdle": "#FFFFFFC7", "control": "#BDBDC2",
        "artworkTint": "#3A3A3E", "display": "#BFC8EE"])

    public static let wine = ThemeFile(id: "wine", name: "Vinho", author: "Wineup", colors: [
        "windowTop": "#4A1A1E", "windowBottom": "#24090D", "panelFill": "#5A1F258C", "panelBorder": "#FFFFFF26",
        "text": "#F6E9E9", "mutedText": "#C9A9AC", "accent": "#FF5A4D", "rowSelection": "#FFFFFF29",
        "currentRow": "#FFD27A", "lyricsActive": "#FFE3B0", "lyricsIdle": "#E9CFCF", "control": "#E2C4C6",
        "artworkTint": "#7A2A31", "display": "#FFD9C2"])

    public static let green = ThemeFile(id: "green", name: "Verde", author: "Wineup", colors: [
        "windowTop": "#0F2A26", "windowBottom": "#08181A", "panelFill": "#143530D9", "panelBorder": "#7CE3A147",
        "text": "#8FF0A8", "mutedText": "#5DBB7E", "accent": "#CFEFD9", "rowSelection": "#7CE3A133",
        "currentRow": "#B6FFC8", "lyricsActive": "#9CFFB0", "lyricsIdle": "#7CE39A", "control": "#8FE3A8",
        "artworkTint": "#1F5C4A", "display": "#9CFFB0"])

    public static let builtIns: [ThemeFile] = [.graphite, .wine, .green]

    public init(id: String, name: String, author: String = "", colors: [String: String]) {
        self.id = id; self.name = name; self.author = author; self.colors = colors
    }

    public var isBuiltIn: Bool { Self.builtIns.contains { $0.id == id } }
}



/// Temas embutidos + temas do usuário (pasta Themes em Application Support).
/// Um embutido editado vira um arquivo com o mesmo id, que tem prioridade; "Restaurar original" apaga.
public final class ThemeStore: ObservableObject, @unchecked Sendable {
    public static let shared = ThemeStore()
    public static let fileExtension = "wineuptheme"

    public let folder: URL
    @Published public private(set) var files: [ThemeFile] = []

    public init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Wineup/Themes", isDirectory: true)) {
        self.folder = folder
        reload()
    }

    public func reload() {
        let user = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == Self.fileExtension }
            .compactMap { try? Self.decode(Data(contentsOf: $0)) }
        let byID = Dictionary(user.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let builtIns = ThemeFile.builtIns.map { byID[$0.id] ?? $0 }
        let extra = user.filter { !$0.isBuiltIn }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files = builtIns + extra
    }

    public func file(_ id: String) -> ThemeFile? { files.first { $0.id == id } }

    public func isModifiedBuiltIn(_ id: String) -> Bool {
        guard let builtIn = ThemeFile.builtIns.first(where: { $0.id == id }) else { return false }
        return file(id) != builtIn
    }

    // MARK: Gravar

    public func save(_ file: ThemeFile) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encode(file).write(to: url(for: file.id), options: .atomic)
        reload()
    }

    public func delete(_ id: String) throws {
        let u = url(for: id)
        if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
        reload()
    }

    /// Cópia editável com id e nome novos.
    public func duplicate(_ source: ThemeFile, name: String? = nil) throws -> ThemeFile {
        var copy = source
        copy.id = uniqueID(from: name ?? source.name + " (cópia)")
        copy.name = name ?? source.name + " (cópia)"
        try save(copy)
        return copy
    }

    /// Importa um arquivo; se o id já existe, ganha um novo (não apaga o tema existente).
    public func importTheme(from url: URL) throws -> ThemeFile {
        var theme = try Self.decode(Data(contentsOf: url))
        if file(theme.id) != nil || theme.isBuiltIn { theme.id = uniqueID(from: theme.name) }
        try save(theme)
        return theme
    }

    public func export(_ theme: ThemeFile, to url: URL) throws {
        try Self.encode(theme).write(to: url, options: .atomic)
    }

    private func url(for id: String) -> URL { folder.appendingPathComponent("\(id).\(Self.fileExtension)") }

    private func uniqueID(from name: String) -> String {
        let base = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) }
            .split(separator: "-").joined(separator: "-")
        var id = base.isEmpty ? "tema" : base
        var n = 2
        while file(id) != nil || ThemeFile.builtIns.contains(where: { $0.id == id }) { id = "\(base)-\(n)"; n += 1 }
        return id
    }

    public static func encode(_ file: ThemeFile) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(file)
    }

    public static func decode(_ data: Data) throws -> ThemeFile {
        let theme = try JSONDecoder().decode(ThemeFile.self, from: data)
        guard theme.format == "wineup-theme", !theme.id.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return theme
    }
}
