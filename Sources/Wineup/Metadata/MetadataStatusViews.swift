import SwiftUI
import WineupLibrary

/// Cor e símbolo do estado de uma música, num lugar só (selo da capa, cards do rodapé, legenda).
enum RowLook {
    case searching, complete, incomplete, review, notFound, failed

    init(_ row: MetadataRow) {
        switch row.status {
        case .searching: self = .searching
        case .failed: self = .failed
        case .notFound where !row.isDirty: self = .notFound
        case .review where !row.isDirty: self = .review
        default: self = row.isComplete && !row.isDirty ? .complete : .incomplete
        }
    }

    var symbol: String {
        switch self {
        case .searching: "ellipsis"
        case .complete: "checkmark"
        case .incomplete: "exclamationmark"
        case .review: "questionmark"
        case .notFound: "minus"
        case .failed: "xmark"
        }
    }

    var color: Color {
        switch self {
        case .searching: .secondary
        case .complete: .green
        case .incomplete: .yellow
        case .review: .orange
        case .notFound, .failed: .red
        }
    }

    static func tooltip(_ row: MetadataRow) -> String {
        var parts: [String] = []
        switch RowLook(row) {
        case .searching: parts.append(String(localized: "Buscando dados…"))
        case .complete: parts.append(row.status == .saved ? String(localized: "Salva e completa")
                                  : String(localized: "Completa: título, artista, álbum, ano, faixa, gênero, capa e letra"))
        case .incomplete: parts.append(String(localized: "Falta: \(row.missingEssentials.joined(separator: ", "))"))
        case .review: parts.append(String(localized: "Encontrada com pouca confiança: clique duas vezes para escolher o resultado"))
        case .notFound: parts.append(String(localized: "Nada encontrado nas bases"))
        case .failed: parts.append(row.status.label)
        }
        if row.isDirty { parts.append(String(localized: "Encontrado, ainda não gravado: \(row.foundItems.joined(separator: ", "))")) }
        return parts.joined(separator: "\n")
    }
}

/// Bolinha azul antes da capa: a busca trouxe dados que ainda não foram gravados.
struct FoundDot: View {
    let visible: Bool

    var body: some View {
        ZStack {
            if visible {
                Image(systemName: "arrow.down")
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 10, height: 10)
                    .background(Circle().fill(Color.accentColor))
                    .transition(.scale.combined(with: .opacity))
                    .help("Dados encontrados, ainda não gravados")
            }
        }
        .frame(width: 10)
    }
}

/// Confiança da busca, curta, antes do nome (verde ≥ 80 %, laranja ≥ 60 %, vermelha abaixo).
struct ConfidenceChip: View {
    let value: Double

    var body: some View {
        Text("\(Int((value * 100).rounded()))%")
            .font(.system(size: 9, weight: .semibold)).monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(color))
            .help("Confiança da correspondência encontrada")
    }

    private var color: Color {
        value >= MetadataFixer.autoApplyConfidence ? .green : value >= 0.6 ? .orange : .red
    }
}

/// Miniatura da capa com o selo de estado no canto.
struct RowThumb: View {
    let row: MetadataRow
    var size: CGFloat = 16
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.medium).scaledToFill()
                } else {
                    Image(systemName: "music.note").font(.system(size: size * 0.55)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.15))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(2, size / 8)))
            StatusBadge(row: row, size: max(10, size * 0.6)).offset(x: size * 0.25, y: size * 0.18)
        }
        .frame(width: size + 4, height: size + 1)
        .help(RowLook.tooltip(row))
        .task(id: "\(row.id)|\(row.cover?.data.count ?? -1)|\(row.file.coverBytes)") {
            image = await ThumbnailCache.shared.thumbnail(for: row)
        }
    }
}

/// Selo de estado: verde completa, amarelo falta algo, laranja revisar, vermelho nada encontrado ou erro.
struct StatusBadge: View {
    let row: MetadataRow
    var size: CGFloat = 10

    var body: some View {
        let look = RowLook(row)
        Group {
            if look == .searching {
                ProgressView().controlSize(.mini).scaleEffect(size / 16).frame(width: size, height: size)
            } else {
                Image(systemName: look.symbol)
                    .font(.system(size: size * 0.6, weight: .black))
                    .foregroundStyle(look == .incomplete ? Color.black.opacity(0.75) : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: size, height: size)
                    .background(Circle().fill(look.color))
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
            }
        }
        .animation(.snappy, value: look)
    }
}

/// Coluna Letra: símbolo, cor e explicação ao passar o mouse (célula em MetadataCells).
enum LyricsFlag {
    /// Relógio verde = sincronizada; texto laranja = estática; traço vermelho = sem letra; azul = nova, não gravada.
    static func look(_ row: MetadataRow) -> (symbol: String, color: Color, tooltip: String) {
        let synced = row.lyrics.map(\.isSynced) ?? row.file.lyricsSynced
        let pending = row.lyrics?.text != nil
        let symbol = synced == true ? "clock.fill" : synced == false ? "text.alignleft" : "minus.circle"
        let color = pending ? Color.accentColor : synced == true ? .green : synced == false ? .orange : Color.red.opacity(0.8)
        return (symbol, color, explanation(synced: synced, pending: pending))
    }

    private static func explanation(synced: Bool?, pending: Bool) -> String {
        let state = switch synced {
        case true?: String(localized: "Letra sincronizada: acompanha a música linha a linha (relógio verde).")
        case false?: String(localized: "Letra estática: o texto existe, mas sem marcas de tempo (ícone laranja).")
        case nil: String(localized: "Sem letra (traço vermelho). Busque em Corrigir tudo, ou na seção Letra ao lado.")
        }
        return pending ? state + "\n" + String(localized: "Em azul: letra nova encontrada, gravada ao salvar.") : state
    }
}
