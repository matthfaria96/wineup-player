import Combine
import Foundation

/// Skin do Wineup (.wineupskin): uma pasta (ou ZIP dela) com `skin.json` e os arquivos de arte.
///
///     skin.json        manifesto (este tipo)
///     *.jpg / *.png    fundos, texturas dos painéis, molduras, botões, puxador
///     *.ttf / *.otf    fontes próprias
///
/// Tudo é opcional, menos `format`, `id` e `name`: o que faltar usa o padrão do app.
public struct SkinManifest: Codable, Equatable, Sendable, Identifiable {
    public var format = "wineup-skin"
    public var version = 1
    public var id: String
    public var name: String
    public var author: String = ""
    public var description: String = ""
    public var credits: [Credit] = []
    /// Cores por token (ColorToken.rawValue → "#RRGGBB" ou "#RRGGBBAA").
    public var colors: [String: String] = [:]
    public var window = Window()
    /// Estilo por painel ("default", "player", "equalizer", "playlist", "artwork", "lyrics").
    public var panels: [String: PanelStyle] = [:]
    public var controls = Controls()
    public var display = Display()
    public var fonts: [String] = []
    /// Fonte dos títulos (nome PostScript ou de família) e do texto comum.
    public var titleFont: FontRef?
    public var bodyFont: FontRef?

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public struct Credit: Codable, Equatable, Sendable {
        public var work: String
        public var author: String
        public var license: String
        public var source: String
        public init(work: String, author: String, license: String, source: String) {
            self.work = work; self.author = author; self.license = license; self.source = source
        }
    }

    public struct FontRef: Codable, Equatable, Sendable {
        public var name: String
        public var size: Double?
        public var weight: String?
        public init(name: String, size: Double? = nil, weight: String? = nil) { self.name = name; self.size = size; self.weight = weight }
    }

    /// Imagem que preenche uma área (fundo da janela, de um painel).
    public struct Fill: Codable, Equatable, Sendable {
        public var image: String
        /// Escurece por cima (0...1) para o texto ficar legível.
        public var dim: Double = 0
        public var blur: Double = 0
        /// Ponto de foco do recorte (0...1), para "fill".
        public var focusX: Double = 0.5
        public var focusY: Double = 0.5
        public init(image: String, dim: Double = 0, blur: Double = 0, focusX: Double = 0.5, focusY: Double = 0.5) {
            self.image = image; self.dim = dim; self.blur = blur; self.focusX = focusX; self.focusY = focusY
        }
    }

    /// Imagem de 9 fatias: `slice` = tamanho dos cantos na imagem (px); `width` = espessura desenhada (pt).
    public struct NineSlice: Codable, Equatable, Sendable {
        public var image: String
        public var slice: Double
        public var width: Double
        public init(image: String, slice: Double, width: Double) { self.image = image; self.slice = slice; self.width = width }
    }

    public struct Window: Codable, Equatable, Sendable {
        public var background: Fill?
        public var layers: [Layer] = []
        public init(background: Fill? = nil, layers: [Layer] = []) { self.background = background; self.layers = layers }
    }

    public struct PanelStyle: Codable, Equatable, Sendable {
        public var fill: Fill?
        public var frame: NineSlice?
        public var cornerRadius: Double?
        public var layers: [Layer] = []
        public init(fill: Fill? = nil, frame: NineSlice? = nil, cornerRadius: Double? = nil, layers: [Layer] = []) {
            self.fill = fill; self.frame = frame; self.cornerRadius = cornerRadius; self.layers = layers
        }
    }

    public struct Controls: Codable, Equatable, Sendable {
        public var button: NineSlice?
        public var buttonOn: NineSlice?
        public var knob: String?
        public var knobSize: Double?
        /// Campo de texto (busca), em 9 fatias.
        public var field: NineSlice?
        public init() {}
    }

    public struct Display: Codable, Equatable, Sendable {
        /// Brilho em volta do visor (0...1).
        public var glow: Double = 0
        public init() {}
    }

    /// Camada animada por cima de um fundo. Pontos em frações (0...1) da área.
    public struct Layer: Codable, Equatable, Sendable, Identifiable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            /// Estrelas que pulsam e soltam raios (pontos dados ou espalhadas).
            case stars
            /// Brilho em espiral girando em volta de um ponto (redemoinhos de céu, portais).
            case swirl
            /// Halo que respira em volta de um ponto (lua, sol, lanternas).
            case glow
            /// Pinceladas/partículas que correm na diagonal, como vento ou fluxo.
            case flow
            /// Uma imagem do skin que flutua, gira ou pulsa (personagem, logo, ornamento).
            case image
        }

        public var id: String { "\(kind.rawValue)-\(name ?? "")" }
        public var kind: Kind
        public var name: String?
        public var enabled = true
        public var points: [Point] = []
        public var color: String?
        public var colors: [String] = []
        /// Velocidade (1 = normal).
        public var speed = 1.0
        /// Intensidade (0...1).
        public var intensity = 0.7
        /// Reage à música (mais brilho e velocidade com o volume).
        public var react = true
        public var count: Int?
        public var image: String?
        /// Animação da camada `image`: "float", "spin", "pulse", "none".
        public var motion: String?

        public init(kind: Kind, name: String? = nil, points: [Point] = [], color: String? = nil, colors: [String] = [],
                    speed: Double = 1, intensity: Double = 0.7, react: Bool = true, count: Int? = nil,
                    image: String? = nil, motion: String? = nil) {
            self.kind = kind; self.name = name; self.points = points; self.color = color; self.colors = colors
            self.speed = speed; self.intensity = intensity; self.react = react; self.count = count
            self.image = image; self.motion = motion
        }
    }

    public struct Point: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var r: Double
        public init(x: Double, y: Double, r: Double) { self.x = x; self.y = y; self.r = r }
    }

    /// Tokens de cor (os mesmos de sempre: o skin pode mudar qualquer um).
    public enum ColorToken: String, CaseIterable, Identifiable, Sendable {
        case windowTop, windowBottom, panelFill, panelBorder, text, mutedText, accent
        case rowSelection, currentRow, lyricsActive, lyricsIdle, control, artworkTint, display
        case buttonText, buttonTextOn

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
            case .control: "Controles"
            case .artworkTint: "Fundo da capa"
            case .display: "Visor (relógio)"
            case .buttonText: "Texto dos botões"
            case .buttonTextOn: "Texto dos botões ligados"
            }
        }
    }

    /// Cores usadas quando o skin não define um token (neutras, escuras).
    public static let fallbackColors: [String: String] = [
        "windowTop": "#1E1E20", "windowBottom": "#141416", "panelFill": "#252527EB", "panelBorder": "#FFFFFF1F",
        "text": "#FFFFFF", "mutedText": "#9A9A9E", "accent": "#E5322D", "rowSelection": "#FFFFFF24",
        "currentRow": "#FF3B30", "lyricsActive": "#FFFFFF", "lyricsIdle": "#FFFFFFC7", "control": "#BDBDC2",
        "artworkTint": "#3A3A3E", "display": "#BFC8EE",
        "buttonText": "#FFFFFF", "buttonTextOn": "#FFFFFF"]

    public func panelStyle(_ panel: String) -> PanelStyle? { panels[panel] ?? panels["default"] }

    /// Todos os arquivos que o manifesto cita (para validar e exportar).
    public var referencedFiles: [String] {
        var out = fonts
        if let b = window.background?.image { out.append(b) }
        out += window.layers.compactMap(\.image)
        for p in panels.values {
            if let f = p.fill?.image { out.append(f) }
            if let f = p.frame?.image { out.append(f) }
            out += p.layers.compactMap(\.image)
        }
        out += [controls.button?.image, controls.buttonOn?.image, controls.knob, controls.field?.image].compactMap { $0 }
        return Array(Set(out)).sorted()
    }
}

/// Um skin instalado: manifesto + pasta onde estão os arquivos.
public struct Skin: Identifiable, Equatable, Sendable {
    public var manifest: SkinManifest
    public var folder: URL
    public var builtIn: Bool

    public var id: String { manifest.id }
    public var name: String { manifest.name }

    public func file(_ name: String) -> URL { folder.appendingPathComponent(name) }
}

/// Skins embutidos (pasta Skins dentro do app) + skins do usuário (Application Support/Wineup/Skins).
/// Editar um embutido cria a versão do usuário (mesmo id), que tem prioridade; "Restaurar original" a apaga.
public final class SkinStore: ObservableObject, @unchecked Sendable {
    public static let shared = SkinStore()
    public static let fileExtension = "wineupskin"
    public static let defaultID = "noite-estrelada"

    public let builtInFolder: URL?
    /// Skins do usuário (criados, duplicados, importados).
    public let userFolder: URL
    /// Ajustes do usuário nos skins oficiais: pasta separada, para nunca se misturarem com os dele.
    public let officialEditsFolder: URL
    @Published public private(set) var skins: [Skin] = []

    public init(builtInFolder: URL? = Bundle.main.resourceURL?.appendingPathComponent("Skins"),
                userFolder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Wineup/Skins", isDirectory: true)) {
        self.builtInFolder = builtInFolder
        self.userFolder = userFolder
        officialEditsFolder = userFolder.deletingLastPathComponent().appendingPathComponent("Ajustes dos skins oficiais", isDirectory: true)
        migrateOfficialEdits()
        reload()
    }

    /// Versões antigas guardavam o oficial editado junto dos skins do usuário: move para a pasta própria.
    private func migrateOfficialEdits() {
        let officialIDs = Set(Self.load(in: builtInFolder, builtIn: true).map(\.id))
        for skin in Self.load(in: userFolder, builtIn: false) where officialIDs.contains(skin.id) {
            try? FileManager.default.createDirectory(at: officialEditsFolder, withIntermediateDirectories: true)
            let dest = officialEditsFolder.appendingPathComponent(skin.id, isDirectory: true)
            if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: skin.folder) }
            else { try? FileManager.default.moveItem(at: skin.folder, to: dest) }
        }
    }

    public func reload() {
        let builtIns = Self.load(in: builtInFolder, builtIn: true)
        let edits = Self.load(in: officialEditsFolder, builtIn: true)
        let officialIDs = Set(builtIns.map(\.id))
        skins = builtIns.map { b in edits.first { $0.id == b.id } ?? b }
            + Self.load(in: userFolder, builtIn: false).filter { !officialIDs.contains($0.id) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func skin(_ id: String) -> Skin? { skins.first { $0.id == id } }

    /// Skin oficial (vem com o app): pode ser ajustado e restaurado, nunca apagado.
    public func isBuiltInID(_ id: String) -> Bool { Self.load(in: builtInFolder, builtIn: true).contains { $0.id == id } }
    public func isOfficial(_ id: String) -> Bool { isBuiltInID(id) }

    /// O usuário ajustou este oficial.
    public func isModifiedBuiltIn(_ id: String) -> Bool {
        isBuiltInID(id) && FileManager.default.fileExists(atPath: officialEditsFolder.appendingPathComponent(id).path)
    }

    static func load(in folder: URL?, builtIn: Bool) -> [Skin] {
        guard let folder else { return [] }
        let dirs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return dirs.compactMap { dir in
            guard let manifest = try? decode(Data(contentsOf: dir.appendingPathComponent("skin.json"))) else { return nil }
            return Skin(manifest: manifest, folder: dir, builtIn: builtIn)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Editar

    /// Pasta onde as edições deste skin são gravadas (cópia do oficial na pasta de ajustes, ou o próprio do usuário).
    @discardableResult
    public func editableFolder(for id: String) throws -> URL {
        let base = isOfficial(id) ? officialEditsFolder : userFolder
        let dest = base.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        guard let source = skin(id) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source.folder, to: dest)
        return dest
    }

    public func save(_ manifest: SkinManifest) throws {
        let folder = try editableFolder(for: manifest.id)
        try Self.encode(manifest).write(to: folder.appendingPathComponent("skin.json"), options: .atomic)
        reload()
    }

    /// Copia um arquivo de arte para o skin (editável) e devolve o nome usado no manifesto.
    public func addAsset(_ file: URL, to id: String) throws -> String {
        let folder = try editableFolder(for: id)
        var name = file.lastPathComponent
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(file.deletingPathExtension().lastPathComponent)-\(n).\(file.pathExtension)"; n += 1
        }
        try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(name))
        return name
    }

    public func duplicate(_ id: String, name: String) throws -> Skin {
        guard let source = skin(id) else { throw CocoaError(.fileNoSuchFile) }
        var manifest = source.manifest
        manifest.id = uniqueID(from: name)
        manifest.name = name
        let dest = userFolder.appendingPathComponent(manifest.id, isDirectory: true)
        try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source.folder, to: dest)
        try Self.encode(manifest).write(to: dest.appendingPathComponent("skin.json"), options: .atomic)
        reload()
        return skin(manifest.id)!
    }

    /// Apaga um skin do usuário. Oficiais não podem ser apagados (use `restoreOfficial`).
    public func delete(_ id: String) throws {
        guard !isOfficial(id) else { throw CocoaError(.fileWriteNoPermission) }
        let dir = userFolder.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
        reload()
    }

    /// Desfaz todos os ajustes do usuário num skin oficial.
    public func restoreOfficial(_ id: String) throws {
        let dir = officialEditsFolder.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
        reload()
    }

    // MARK: Importar / exportar (.wineupskin = ZIP da pasta)

    /// Abre o pacote numa pasta temporária, sem instalar (para a tela "Sobre o skin").
    /// Quem chama apaga `skin.folder.deletingLastPathComponent()` quando terminar.
    public func inspect(_ archive: URL) throws -> Skin {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wineup-skin-\(UUID().uuidString)", isDirectory: true)
        try Self.ditto(["-x", "-k", archive.path, tmp.path])
        guard let root = Self.findManifestFolder(in: tmp) else { try? FileManager.default.removeItem(at: tmp); throw CocoaError(.fileReadCorruptFile) }
        let manifest = try Self.decode(Data(contentsOf: root.appendingPathComponent("skin.json")))
        guard manifest.referencedFiles.allSatisfy({ !$0.contains("..") && !$0.hasPrefix("/") }) else {
            try? FileManager.default.removeItem(at: tmp); throw CocoaError(.fileReadCorruptFile)
        }
        return Skin(manifest: manifest, folder: root, builtIn: false)
    }

    /// Já existe um skin com este id (instalar cria uma cópia com outro id).
    public func isInstalled(_ id: String) -> Bool { skin(id) != nil }

    public func importSkin(from archive: URL) throws -> Skin {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Self.ditto(["-x", "-k", archive.path, tmp.path])
        guard let root = Self.findManifestFolder(in: tmp) else { throw CocoaError(.fileReadCorruptFile) }
        var manifest = try Self.decode(Data(contentsOf: root.appendingPathComponent("skin.json")))
        // Só caminhos simples dentro da pasta (nada de ../).
        guard manifest.referencedFiles.allSatisfy({ !$0.contains("..") && !$0.hasPrefix("/") }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if skin(manifest.id) != nil { manifest.id = uniqueID(from: manifest.name) }
        let dest = userFolder.appendingPathComponent(manifest.id, isDirectory: true)
        try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root, to: dest)
        try Self.encode(manifest).write(to: dest.appendingPathComponent("skin.json"), options: .atomic)
        reload()
        return skin(manifest.id)!
    }

    public func export(_ id: String, to archive: URL) throws {
        guard let s = skin(id) else { throw CocoaError(.fileNoSuchFile) }
        if FileManager.default.fileExists(atPath: archive.path) { try FileManager.default.removeItem(at: archive) }
        try Self.ditto(["-c", "-k", "--sequesterRsrc", "--keepParent", s.folder.path, archive.path])
    }

    static func findManifestFolder(in dir: URL) -> URL? {
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("skin.json").path) { return dir }
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while let u = e?.nextObject() as? URL {
            if u.lastPathComponent == "skin.json", !u.path.contains("__MACOSX") { return u.deletingLastPathComponent() }
        }
        return nil
    }

    static func ditto(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    public func uniqueIDPublic(from name: String) -> String { uniqueID(from: name) }

    private func uniqueID(from name: String) -> String {
        let base = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) }
            .split(separator: "-").joined(separator: "-")
        var id = base.isEmpty ? "skin" : base
        var n = 2
        while skin(id) != nil || isOfficial(id) { id = "\(base)-\(n)"; n += 1 }
        return id
    }

    public static func encode(_ m: SkinManifest) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(m)
    }

    public static func decode(_ data: Data) throws -> SkinManifest {
        let m = try JSONDecoder().decode(SkinManifest.self, from: data)
        guard m.format == "wineup-skin", !m.id.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return m
    }
}

// MARK: Leitura tolerante: chave ausente = valor padrão (o skin só escreve o que muda).

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) throws -> T { try decodeIfPresent(T.self, forKey: key) ?? fallback }
}

extension SkinManifest {
    enum CodingKeys: String, CodingKey {
        case format, version, id, name, author, description, credits, colors, window, panels, controls, display, fonts, titleFont, bodyFont
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name))
        format = try c.value(.format, "wineup-skin"); version = try c.value(.version, 1)
        author = try c.value(.author, ""); description = try c.value(.description, "")
        credits = try c.value(.credits, []); colors = try c.value(.colors, [:])
        window = try c.value(.window, Window()); panels = try c.value(.panels, [:])
        controls = try c.value(.controls, Controls()); display = try c.value(.display, Display())
        fonts = try c.value(.fonts, [])
        titleFont = try c.decodeIfPresent(FontRef.self, forKey: .titleFont)
        bodyFont = try c.decodeIfPresent(FontRef.self, forKey: .bodyFont)
    }
}

extension SkinManifest.Fill {
    enum CodingKeys: String, CodingKey { case image, dim, blur, focusX, focusY }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(image: try c.decode(String.self, forKey: .image), dim: try c.value(.dim, 0), blur: try c.value(.blur, 0),
                  focusX: try c.value(.focusX, 0.5), focusY: try c.value(.focusY, 0.5))
    }
}

extension SkinManifest.Window {
    enum CodingKeys: String, CodingKey { case background, layers }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(background: try c.decodeIfPresent(SkinManifest.Fill.self, forKey: .background), layers: try c.value(.layers, []))
    }
}

extension SkinManifest.PanelStyle {
    enum CodingKeys: String, CodingKey { case fill, frame, cornerRadius, layers }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(fill: try c.decodeIfPresent(SkinManifest.Fill.self, forKey: .fill),
                  frame: try c.decodeIfPresent(SkinManifest.NineSlice.self, forKey: .frame),
                  cornerRadius: try c.decodeIfPresent(Double.self, forKey: .cornerRadius), layers: try c.value(.layers, []))
    }
}

extension SkinManifest.Controls {
    enum CodingKeys: String, CodingKey { case button, buttonOn, knob, knobSize, field }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        button = try c.decodeIfPresent(SkinManifest.NineSlice.self, forKey: .button)
        buttonOn = try c.decodeIfPresent(SkinManifest.NineSlice.self, forKey: .buttonOn)
        knob = try c.decodeIfPresent(String.self, forKey: .knob)
        knobSize = try c.decodeIfPresent(Double.self, forKey: .knobSize)
        field = try c.decodeIfPresent(SkinManifest.NineSlice.self, forKey: .field)
    }
}

extension SkinManifest.Display {
    enum CodingKeys: String, CodingKey { case glow }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        glow = try c.value(.glow, 0)
    }
}

extension SkinManifest.Layer {
    enum CodingKeys: String, CodingKey { case kind, name, enabled, points, color, colors, speed, intensity, react, count, image, motion }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try c.decode(Kind.self, forKey: .kind), name: try c.decodeIfPresent(String.self, forKey: .name),
                  points: try c.value(.points, []), color: try c.decodeIfPresent(String.self, forKey: .color),
                  colors: try c.value(.colors, []), speed: try c.value(.speed, 1), intensity: try c.value(.intensity, 0.7),
                  react: try c.value(.react, true), count: try c.decodeIfPresent(Int.self, forKey: .count),
                  image: try c.decodeIfPresent(String.self, forKey: .image), motion: try c.decodeIfPresent(String.self, forKey: .motion))
        enabled = try c.value(.enabled, true)
    }
}
