import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Painéis que podem ser rearranjados.
enum PanelKind: String, CaseIterable, Codable {
    case player, equalizer, playlist, artwork, lyrics

    /// Altura fixa (player e mixer); os demais ocupam o espaço que sobra na coluna.
    var fixedHeight: CGFloat? {
        switch self {
        case .player: 236
        case .equalizer: 190
        default: nil
        }
    }

    var hasTitleBar: Bool { self != .playlist }
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
             PanelColumn(panels: [.lyrics], width: 420)]
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

    /// Arrastar `source` sobre `target` (devolve um novo arranjo, sem mutar o original):
    /// - mesma coluna (de cima para baixo): troca só os dois painéis;
    /// - outra coluna (para o lado): troca as colunas inteiras, cada uma com a sua largura.
    ///   Player, mixer e capa andam juntos; a letra anda inteira.
    func moving(_ source: PanelKind, onto target: PanelKind, in columns: [PanelColumn]) -> [PanelColumn] {
        guard source != target,
              let from = columns.firstIndex(where: { $0.panels.contains(source) }),
              let to = columns.firstIndex(where: { $0.panels.contains(target) }) else { return columns }
        if from == to {
            return columns.map { column in
                PanelColumn(panels: column.panels.map { $0 == source ? target : ($0 == target ? source : $0) },
                            width: column.width)
            }
        }
        var out = columns
        out.swapAt(from, to)
        return out
    }

    /// Se soltar `source` em `target` troca a coluna inteira (e não só o painel).
    static func movesWholeColumn(_ source: PanelKind, onto target: PanelKind, in columns: [PanelColumn]) -> Bool {
        columns.firstIndex { $0.panels.contains(source) } != columns.firstIndex { $0.panels.contains(target) }
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
                // Arrasto vindo de outra coluna: a coluna inteira é que vai trocar de lugar.
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                        .padding(-3)
                        .opacity(columnTargeted(column) ? 1 : 0)
                )
                .animation(.easeOut(duration: 0.12), value: drop.targeted)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: columns)
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
                        .onDrag {
                            drop.dragging = kind
                            return NSItemProvider(object: kind.rawValue as NSString)
                        }
                        .help("Arraste para o lado para mover a coluna inteira; para cima ou para baixo para trocar este painel")
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .opacity(drop.targeted == kind && !wholeColumn(onto: kind) ? 1 : 0)
            )
            .onDrop(of: [.text], delegate: PanelDrop(target: kind, targeted: $drop.targeted) { source in
                drop.dragging = nil
                let moved = mode.moving(source, onto: kind, in: columns)
                columns = moved
                mode.save(moved)
            })
    }

    private func wholeColumn(onto target: PanelKind) -> Bool {
        guard let source = drop.dragging else { return false }
        return LayoutMode.movesWholeColumn(source, onto: target, in: columns)
    }

    private func columnTargeted(_ column: PanelColumn) -> Bool {
        guard let target = drop.targeted, column.panels.contains(target) else { return false }
        return wholeColumn(onto: target)
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
                  source != target else { return }
            DispatchQueue.main.async { onSwap(source) }
        }
        return true
    }
}

/// Painel sob o arrasto (para o destaque); evita `@State`, que é macro sem plugin nas CLT.
final class DropHighlight: ObservableObject {
    @Published var targeted: PanelKind?
    /// Painel sendo arrastado (para saber se o destino troca o painel ou a coluna).
    var dragging: PanelKind?
}

/// Estado local da janela principal (colunas e NSWindow).
final class MainViewModel: ObservableObject {
    @Published var columns: [PanelColumn] = LayoutMode.standard.columns()
    var window: NSWindow?
}
