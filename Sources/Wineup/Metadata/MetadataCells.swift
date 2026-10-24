import AppKit
import SwiftUI
import WineupLibrary

// Células da lista de Metadados em AppKit, com layout por frame: a lista recarrega dezenas de células
// a cada ordenação ou filtro, e células em SwiftUI (NSHostingView) custavam ~60 ms de layout por recarga.

/// Base: coordenadas de cima para baixo e nada de Auto Layout.
class MetadataCellBase: NSTableCellView {
    override var isFlipped: Bool { true }

    static func label() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.cell?.truncatesLastVisibleLine = true
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    /// Centraliza na vertical um elemento de altura `height` a partir de `x`.
    func centered(_ x: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
    }
}

/// Texto simples de uma coluna.
final class MetadataTextCell: MetadataCellBase {
    static let identifier = NSUserInterfaceItemIdentifier("metadata.text")
    private let label = MetadataCellBase.label()

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    override func layout() {
        super.layout()
        let height = ceil(label.intrinsicContentSize.height)
        label.frame = centered(2, width: max(0, bounds.width - 4), height: height)
    }

    func configure(_ value: String, edited: Bool, tooltip: String?, column: MetadataColumn) {
        label.stringValue = value
        label.alignment = column.alignment
        label.lineBreakMode = column.truncatesHead ? .byTruncatingHead : .byTruncatingTail
        let weight: NSFont.Weight = edited ? .semibold : .regular
        label.font = column.monospaced ? .monospacedDigitSystemFont(ofSize: 11, weight: weight) : .systemFont(ofSize: 11, weight: weight)
        label.textColor = edited ? .controlAccentColor : .labelColor
        toolTip = tooltip
        needsLayout = true
    }
}

/// Nome do arquivo: bolinha azul (dados encontrados), capa com selo de estado, confiança e nome.
final class MetadataNameCell: MetadataCellBase {
    static let identifier = NSUserInterfaceItemIdentifier("metadata.name")
    private let dot = CircleView()
    private let dotArrow = NSImageView()
    private let thumb = NSImageView()
    private let placeholder = NSImageView()
    private let badge = CircleView()
    private let badgeSymbol = NSImageView()
    private let chip = MetadataCellBase.label()
    private let name = MetadataCellBase.label()
    private var thumbKey: String?
    private var thumbTask: Task<Void, Never>?

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        dot.fill = .controlAccentColor
        dotArrow.image = Self.symbol("arrow.down", size: 6, weight: .black)
        dotArrow.contentTintColor = .white
        dot.addSubview(dotArrow)
        dot.toolTip = String(localized: "Dados encontrados, ainda não gravados")
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 2
        thumb.layer?.masksToBounds = true
        placeholder.image = Self.symbol("music.note", size: 9, weight: .regular)
        placeholder.contentTintColor = .secondaryLabelColor
        placeholder.wantsLayer = true
        placeholder.layer?.cornerRadius = 2
        placeholder.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.15).cgColor
        badge.stroke = .windowBackgroundColor
        badge.addSubview(badgeSymbol)
        chip.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        chip.textColor = .white
        chip.alignment = .center
        chip.drawsBackground = false
        chip.wantsLayer = true
        chip.toolTip = String(localized: "Confiança da correspondência encontrada")
        name.font = .systemFont(ofSize: 11)
        for view in [dot, placeholder, thumb, badge, chip, name] as [NSView] { addSubview(view) }
        textField = name
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    func configure(_ row: MetadataRow) {
        dot.isHidden = !row.isDirty
        let look = RowLook(row)
        badge.fill = NSColor(look.color)
        badgeSymbol.image = Self.symbol(look.symbol, size: 6, weight: .black)
        badgeSymbol.contentTintColor = look == .incomplete ? NSColor.black.withAlphaComponent(0.75) : .white
        let tip = RowLook.tooltip(row)
        thumb.toolTip = tip
        placeholder.toolTip = tip
        badge.toolTip = tip
        if let c = row.confidence {
            chip.isHidden = false
            chip.stringValue = String(localized: "\(Int((c * 100).rounded()))%")
            chip.layer?.backgroundColor = (c >= MetadataFixer.autoApplyConfidence ? NSColor.systemGreen
                                           : c >= 0.6 ? NSColor.systemOrange : NSColor.systemRed).cgColor
        } else {
            chip.isHidden = true
        }
        name.stringValue = row.fileName
        name.toolTip = row.url.path
        loadThumbnail(row)
        needsLayout = true
    }

    /// Capa em miniatura, lida fora da thread principal; a célula reaproveitada ignora respostas antigas.
    private func loadThumbnail(_ row: MetadataRow) {
        let key = ThumbnailCache.key(for: row)
        guard key != thumbKey else { return }
        thumbKey = key
        thumbTask?.cancel()
        if let cached = ThumbnailCache.shared.cached(for: row) {
            thumb.image = cached
            thumb.isHidden = false
            return
        }
        thumb.image = nil
        thumb.isHidden = true
        thumbTask = Task { [weak self] in
            let image = await ThumbnailCache.shared.thumbnail(for: row)
            guard !Task.isCancelled, let self, self.thumbKey == key else { return }
            self.thumb.image = image
            self.thumb.isHidden = image == nil
        }
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 2
        dot.frame = centered(x, width: 10, height: 10)
        dotArrow.frame = dot.bounds
        x += 15
        let art = centered(x, width: 16, height: 16)
        thumb.frame = art
        placeholder.frame = art
        badge.frame = NSRect(x: art.maxX - 6, y: art.maxY - 7, width: 10, height: 10)
        badgeSymbol.frame = badge.bounds
        x += 25
        if !chip.isHidden {
            let width = ceil(chip.intrinsicContentSize.width) + 6
            chip.frame = centered(x, width: width, height: 13)
            chip.layer?.cornerRadius = 6.5
            x += width + 5
        }
        let height = ceil(name.intrinsicContentSize.height)
        name.frame = centered(x, width: max(0, bounds.width - x - 2), height: height)
    }

    /// Símbolos já configurados, guardados (a cada célula configurada, criar a imagem de novo pesava).
    private static var symbols: [String: NSImage] = [:]

    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let key = "\(name)|\(size)|\(weight.rawValue)"
        if let cached = symbols[key] { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
        symbols[key] = image
        return image
    }
}

/// Coluna Letra: símbolo colorido com explicação ao passar o mouse.
final class MetadataLyricsCell: MetadataCellBase {
    static let identifier = NSUserInterfaceItemIdentifier("metadata.lyrics")
    private let icon = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    func configure(_ row: MetadataRow) {
        let look = LyricsFlag.look(row)
        icon.image = MetadataNameCell.symbol(look.symbol, size: 11, weight: .regular)
        icon.contentTintColor = NSColor(look.color)
        toolTip = look.tooltip
    }

    override func layout() {
        super.layout()
        icon.frame = centered(((bounds.width - 14) / 2).rounded(), width: 14, height: 14)
    }
}

/// Círculo preenchido (com contorno opcional) desenhado pela camada.
final class CircleView: NSView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var stroke: NSColor? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        fill.setFill()
        path.fill()
        if let stroke {
            stroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}
