import AppKit
import SwiftUI
import WineupLibrary

/// Lista de arquivos; valores alterados (ainda não gravados) aparecem em destaque.
/// NSTableView própria: a Table do SwiftUI levava ~300 ms para reordenar, filtrar ou encher 5 mil linhas
/// (um "mover linha" por item); aqui a tabela só recarrega as linhas visíveis.
struct MetadataTable: View {
    @ObservedObject var model: MetadataManagerModel
    let onPickMatch: (MetadataRow.ID) -> Void

    var body: some View {
        MetadataNativeTable(model: model, rows: model.visibleRows, stamp: model.listStamp,
                            selection: model.selection, sortOrder: model.sortOrder, onPickMatch: onPickMatch)
            .overlay {
                if model.rows.isEmpty && !model.isLoading {
                    ContentUnavailableView("Nenhuma música", systemImage: "music.note",
                                           description: Text("Escolha uma pasta com músicas no botão Pasta."))
                }
            }
    }
}

private struct MetadataNativeTable: NSViewRepresentable {
    let model: MetadataManagerModel
    let rows: [MetadataRow]
    let stamp: MetadataManagerModel.ListStamp
    let selection: Set<MetadataRow.ID>
    let sortOrder: [KeyPathComparator<MetadataRow>]
    let onPickMatch: (MetadataRow.ID) -> Void

    func makeCoordinator() -> MetadataTableCoordinator { MetadataTableCoordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = context.coordinator.makeTable()
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onPickMatch = onPickMatch
        context.coordinator.update(rows: rows, stamp: stamp, selection: selection, sortOrder: sortOrder)
    }
}

/// Fonte de dados e delegado da tabela; conversa com o modelo (seleção, ordem, colunas, menu).
@MainActor
final class MetadataTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private let model: MetadataManagerModel
    var onPickMatch: ((MetadataRow.ID) -> Void)?
    private weak var table: NSTableView?
    private var rows: [MetadataRow] = []
    private var positions: [MetadataRow.ID: Int] = [:]
    private var stamp: MetadataManagerModel.ListStamp?
    /// Mudanças feitas pelo código (recarga, seleção, ordem) não voltam para o modelo.
    private var syncing = false
    private let columns = Dictionary(uniqueKeysWithValues: MetadataColumn.all.map { ($0.id, $0) })

    init(model: MetadataManagerModel) { self.model = model }

    func makeTable() -> NSTableView {
        let table = MetadataNSTableView()
        table.coordinator = self
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.rowHeight = 22
        table.intercellSpacing = NSSize(width: 6, height: 2)
        for spec in MetadataColumn.all {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.minWidth = spec.minWidth
            column.maxWidth = spec.maxWidth
            column.width = spec.width
            column.headerCell.alignment = spec.alignment
            if spec.sort != nil { column.sortDescriptorPrototype = NSSortDescriptor(key: spec.id, ascending: true) }
            table.addTableColumn(column)
        }
        // Ordem e largura das colunas ficam salvas pela própria tabela; mostrar/esconder, no modelo.
        table.autosaveTableColumns = true
        table.autosaveName = "metadata.nativeTable.v1"
        applyVisibility(to: table)
        let headerMenu = NSMenu()
        headerMenu.delegate = self
        table.headerView?.menu = headerMenu
        let rowMenu = NSMenu()
        rowMenu.delegate = self
        table.menu = rowMenu
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        self.table = table
        return table
    }

    // MARK: Dados vindos do modelo

    func update(rows: [MetadataRow], stamp: MetadataManagerModel.ListStamp, selection: Set<MetadataRow.ID>,
                sortOrder: [KeyPathComparator<MetadataRow>]) {
        guard let table else { return }
        syncing = true
        defer { syncing = false }
        if stamp != self.stamp {
            let firstLoad = self.stamp == nil
            self.stamp = stamp
            let oldCount = self.rows.count
            self.rows = rows
            positions = Dictionary(rows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            if firstLoad {
                table.reloadData()
            } else {
                // Sem reloadData: ele descartava e recriava as ~450 células visíveis (~100 ms).
                // As células que estão na tela só recebem as linhas novas.
                if rows.count != oldCount { table.noteNumberOfRowsChanged() }
                refreshVisibleCells(table)
            }
        }
        let wanted = IndexSet(selection.compactMap { positions[$0] })
        if wanted != table.selectedRowIndexes { table.selectRowIndexes(wanted, byExtendingSelection: false) }
        let descriptors = sortOrder.compactMap { comparator in
            MetadataColumn.column(for: comparator).map { NSSortDescriptor(key: $0.id, ascending: comparator.order == .forward) }
        }
        if descriptors != table.sortDescriptors { table.sortDescriptors = descriptors }
    }

    /// Reaproveita as células que a tabela tem prontas (visíveis e as preparadas em volta) com o conteúdo novo.
    private func refreshVisibleCells(_ table: NSTableView) {
        let specs = table.tableColumns.map { columns[$0.identifier.rawValue] }
        table.enumerateAvailableRowViews { rowView, row in
            guard rows.indices.contains(row) else { return }
            for (index, spec) in specs.enumerated() {
                guard let spec, let view = rowView.view(atColumn: index) as? NSView else { continue }
                configure(view, spec: spec, row: rows[row])
            }
        }
    }

    private func configure(_ view: NSView, spec: MetadataColumn, row: MetadataRow) {
        switch spec.content {
        case .text(let value):
            let shown = value(row)
            (view as? MetadataTextCell)?.configure(shown.value, edited: shown.edited, tooltip: shown.tooltip, column: spec)
        case .name: (view as? MetadataNameCell)?.configure(row)
        case .lyrics: (view as? MetadataLyricsCell)?.configure(row)
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, let spec = columns[id.rawValue], rows.indices.contains(row) else { return nil }
        let cell: NSView
        switch spec.content {
        case .text:
            cell = tableView.makeView(withIdentifier: MetadataTextCell.identifier, owner: self) as? MetadataTextCell
                ?? MetadataTextCell(frame: .zero)
        case .name:
            cell = tableView.makeView(withIdentifier: MetadataNameCell.identifier, owner: self) as? MetadataNameCell
                ?? MetadataNameCell(frame: .zero)
        case .lyrics:
            cell = tableView.makeView(withIdentifier: MetadataLyricsCell.identifier, owner: self) as? MetadataLyricsCell
                ?? MetadataLyricsCell(frame: .zero)
        }
        configure(cell, spec: spec, row: rows[row])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, let table else { return }
        let ids = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
        if ids != model.selection { model.selection = ids }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !syncing else { return }
        let order = tableView.sortDescriptors.compactMap { descriptor in
            descriptor.key.flatMap { columns[$0]?.sort }.map { $0(descriptor.ascending ? .forward : .reverse) }
        }
        if !order.isEmpty { model.sortOrder = order }
    }

    @objc private func doubleClicked() {
        guard let table, rows.indices.contains(table.clickedRow) else { return }
        onPickMatch?(rows[table.clickedRow].id)
    }

    /// Enter com uma música selecionada abre a escolha de resultado (como o clique duplo).
    func primaryAction() {
        guard model.selection.count == 1, let id = model.selection.first else { return }
        onPickMatch?(id)
    }

    // MARK: Colunas visíveis

    private func applyVisibility(to table: NSTableView) {
        for column in table.tableColumns {
            guard let spec = columns[column.identifier.rawValue], spec.hideable else { continue }
            column.isHidden = model.columnCustomization[visibility: spec.id] == .hidden
        }
    }

    private func toggleColumn(_ id: String) {
        guard let table, let column = table.tableColumns.first(where: { $0.identifier.rawValue == id }) else { return }
        column.isHidden.toggle()
        model.columnCustomization[visibility: id] = column.isHidden ? .hidden : .visible
    }

    // MARK: Menus (cabeçalho: colunas; linhas: ações da seleção)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let table else { return }
        if menu === table.headerView?.menu {
            for column in table.tableColumns {
                guard let spec = columns[column.identifier.rawValue], spec.hideable else { continue }
                let item = ActionMenuItem(spec.title) { [weak self] in self?.toggleColumn(spec.id) }
                item.state = column.isHidden ? .off : .on
                menu.addItem(item)
            }
            return
        }
        let clicked = table.clickedRow
        guard rows.indices.contains(clicked) else { return }
        let ids = table.selectedRowIndexes.contains(clicked)
            ? model.selection : [rows[clicked].id]
        buildRowMenu(menu, ids: ids)
    }

    private func buildRowMenu(_ menu: NSMenu, ids: Set<MetadataRow.ID>) {
        let model = model
        menu.addItem(ActionMenuItem(String(localized: "Buscar dados")) { model.selection = ids; model.autoFix(onlySelection: true) })
        if ids.count == 1, let id = ids.first {
            menu.addItem(ActionMenuItem(String(localized: "Escolher resultado…")) { [weak self] in self?.onPickMatch?(id) })
        }
        menu.addItem(ActionMenuItem(String(localized: "Salvar")) { model.selection = ids; model.save(onlySelection: true) })
        menu.addItem(ActionMenuItem(String(localized: "Desfazer alterações")) { model.selection = ids; model.revertSelection() })
        menu.addItem(.separator())
        let ignore = NSMenuItem(title: String(localized: "Ignorar problema"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(ActionMenuItem(String(localized: "Todos os problemas desta seleção")) { model.ignore(nil, ids: ids) })
        sub.addItem(.separator())
        for issue in FixerIssue.allCases {
            sub.addItem(ActionMenuItem(issue.label) { model.ignore(issue, ids: ids) })
        }
        ignore.submenu = sub
        menu.addItem(ignore)
        if model.positions(of: ids).contains(where: { !model.rows[$0].ignored.isEmpty }) {
            menu.addItem(ActionMenuItem(String(localized: "Voltar a mostrar problemas ignorados")) { model.unignore(ids: ids) })
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(String(localized: "Mostrar no Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting(model.positions(of: ids).map { model.rows[$0].url })
        })
    }
}

/// Tabela que avisa o coordenador do Enter (ação principal).
private final class MetadataNSTableView: NSTableView {
    weak var coordinator: MetadataTableCoordinator?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { coordinator?.primaryAction(); return }
        super.keyDown(with: event)
    }
}

/// Item de menu que roda um bloco.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) não usado") }

    @objc private func fire() { handler() }
}

/// Miniaturas pequenas das capas (embutida ou pendente), em memória.
actor ThumbnailCache {
    static let shared = ThumbnailCache()
    /// NSCache é segura entre threads: a célula consulta na hora, sem esperar o ator (sem piscar ao reordenar).
    private nonisolated(unsafe) let cache = NSCache<NSString, NSImage>()

    static func key(for row: MetadataRow) -> String {
        "\(row.id)|\(row.cover?.data.count ?? -1)|\(row.file.coverBytes)"
    }

    nonisolated func cached(for row: MetadataRow) -> NSImage? {
        cache.object(forKey: Self.key(for: row) as NSString)
    }

    func thumbnail(for row: MetadataRow) async -> NSImage? {
        let key = Self.key(for: row) as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let data: Data?
        if let pending = row.cover { data = pending.data }
        else if row.file.hasCover {
            let url = row.url
            data = await Task.detached(priority: .utility) { FolderAnalyzer.embeddedCover(url) }.value
        } else { data = nil }
        guard let data, let image = Self.downsample(data, to: 40) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func downsample(_ data: Data, to pixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
