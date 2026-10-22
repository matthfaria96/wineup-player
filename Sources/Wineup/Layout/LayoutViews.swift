import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Painéis que podem ser rearranjados.
enum PanelKind: String, CaseIterable, Codable {
    case player, equalizer, playlist, artwork, lyrics

    /// Painéis de altura fixa só trocam entre si; os flexíveis também. Assim o layout nunca quebra.
    var fixedHeight: CGFloat? {
        switch self {
        case .player: 236
        case .equalizer: 190
        default: nil
        }
    }

    var hasTitleBar: Bool { self != .playlist }

    func canSwap(with other: PanelKind) -> Bool {
        (fixedHeight == nil) == (other.fixedHeight == nil)
    }
}

/// Coluna do layout: painéis de cima para baixo e largura (nil = flexível).
struct PanelColumn: Codable, Equatable {
    var panels: [PanelKind]
    var width: CGFloat?
}

extension LayoutMode {
    var defaultColumns: [PanelColumn] {
        switch self {
        case .standard:
            [PanelColumn(panels: [.playlist], width: nil),
             PanelColumn(panels: [.player, .equalizer, .artwork], width: 380)]
        case .compact:
            [PanelColumn(panels: [.player, .equalizer, .playlist], width: nil)]
        case .full:
            [PanelColumn(panels: [.playlist], width: nil),
             PanelColumn(panels: [.player, .equalizer, .artwork], width: 380),
             PanelColumn(panels: [.lyrics], width: 320)]
        }
    }

    private var storageKey: String { "panelColumns.\(rawValue)" }

    /// Arranjo salvo pelo usuário (ou o padrão, se o salvo não for válido).
    func columns() -> [PanelColumn] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([PanelColumn].self, from: data),
              saved.flatMap(\.panels).sorted(by: { $0.rawValue < $1.rawValue })
                == defaultColumns.flatMap(\.panels).sorted(by: { $0.rawValue < $1.rawValue })
        else { return defaultColumns }
        return saved
    }

    func save(_ columns: [PanelColumn]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(columns), forKey: storageKey)
    }

    /// Troca dois painéis compatíveis de lugar; devolve um novo arranjo (sem mutar o original).
    func swapping(_ a: PanelKind, _ b: PanelKind, in columns: [PanelColumn]) -> [PanelColumn] {
        guard a != b, a.canSwap(with: b) else { return columns }
        return columns.map { column in
            PanelColumn(panels: column.panels.map { $0 == a ? b : ($0 == b ? a : $0) }, width: column.width)
        }
    }
}

/// Desenha o layout a partir das colunas e permite arrastar painéis pelo título para trocá-los.
struct ArrangedLayout: View {
    @ObservedObject var state: PlayerState
    let mode: LayoutMode
    @Binding var columns: [PanelColumn]
    @StateObject private var drop = DropHighlight()

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: 8) {
                    ForEach(column.panels, id: \.self) { kind in
                        slot(kind)
                    }
                }
                .frame(minWidth: column.width == nil ? 300 : 0, maxWidth: column.width ?? .infinity)
                .frame(width: column.width)
            }
        }
    }

    private func slot(_ kind: PanelKind) -> some View {
        panel(kind)
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: kind.fixedHeight)
            .clipped()
            .overlay(alignment: .top) {
                // Alça de arrasto: a barra de título do painel. A Playlist não tem barra de
                // título (o topo é a navegação), então não recebe alça para não bloquear cliques.
                if kind.hasTitleBar {
                    Color.clear
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        .onDrag { NSItemProvider(object: kind.rawValue as NSString) }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .opacity(drop.targeted == kind ? 1 : 0)
            )
            .onDrop(of: [.text], delegate: PanelDrop(target: kind, targeted: $drop.targeted) { source in
                let swapped = mode.swapping(source, kind, in: columns)
                columns = swapped
                mode.save(swapped)
            })
    }

    @ViewBuilder private func panel(_ kind: PanelKind) -> some View {
        switch kind {
        case .player: PlayerPanel(state: state)
        case .equalizer: EqualizerPanel(state: state)
        case .playlist: PlaylistPanel(state: state, browser: state.browser)
        case .artwork: ArtworkPanel(state: state)
        case .lyrics: LyricsPanel(state: state)
        }
    }
}

private struct PanelDrop: DropDelegate {
    let target: PanelKind
    @Binding var targeted: PanelKind?
    let onSwap: (PanelKind) -> Void

    func dropEntered(info: DropInfo) { targeted = target }
    func dropExited(info: DropInfo) { if targeted == target { targeted = nil } }

    func performDrop(info: DropInfo) -> Bool {
        targeted = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, let source = PanelKind(rawValue: raw),
                  source.canSwap(with: target) else { return }
            DispatchQueue.main.async { onSwap(source) }
        }
        return true
    }
}

/// Painel sob o arrasto (para o destaque); evita `@State`, que é macro sem plugin nas CLT.
final class DropHighlight: ObservableObject {
    @Published var targeted: PanelKind?
}

/// Estado local da janela principal (colunas e NSWindow).
final class MainViewModel: ObservableObject {
    @Published var columns: [PanelColumn] = LayoutMode.standard.columns()
    var window: NSWindow?
}
