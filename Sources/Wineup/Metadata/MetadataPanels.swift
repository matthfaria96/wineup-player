import SwiftUI
import WineupLibrary

/// Barra acima da tabela: a busca trouxe dados; salvar tudo de uma vez ou só ver as alteradas.
struct SaveBanner: View {
    @ObservedObject var model: MetadataManagerModel

    /// Aparece quando há algo para aprovar: alterações prontas para salvar ou resultados para conferir.
    static func isShown(_ model: MetadataManagerModel) -> Bool {
        !model.isBusy && (model.dirtyCount > 0 || model.reviewCount > 0)
    }

    var body: some View {
        let ready = model.dirtyCount
        let review = model.reviewCount
        HStack(spacing: 10) {
            Image(systemName: ready > 0 ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(ready > 0 ? Color.accentColor : .orange)
                .symbolEffect(.bounce, value: ready)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline(ready: ready, review: review))
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.numericText())
                Text(ready > 0
                     ? "Confira na lista: o ponto azul marca o dado novo. Clique duas vezes numa música para trocar o resultado. Antes de gravar, o Wineup guarda um backup de cada arquivo."
                     : "Clique duas vezes numa música para escolher o resultado certo. Nada é gravado até você salvar.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if review > 0 {
                Button("Revisar (\(review))") { withAnimation(.snappy) { model.filter = .review } }
                    .disabled(model.filter == .review)
                    .help("Mostrar só as músicas encontradas com pouca confiança")
            }
            if ready > 0 {
                Button("Ver alteradas") { withAnimation(.snappy) { model.filter = .changed } }
                    .disabled(model.filter == .changed)
                    .help("Mostrar só as músicas que vão ser gravadas")
                Button("Salvar todas") { model.save(onlySelection: false) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.isBusy)
                    .help("Gravar as alterações de todas as músicas (⌘S)")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background((ready > 0 ? Color.accentColor : Color.orange).opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
        .animation(.snappy, value: ready)
        .animation(.snappy, value: review)
    }

    private func headline(ready: Int, review: Int) -> LocalizedStringKey {
        switch (ready, review) {
        case (0, 1): "1 música para revisar"
        case (0, _): "\(review) músicas para revisar"
        case (1, 0): "1 música pronta para salvar"
        case (_, 0): "\(ready) músicas prontas para salvar"
        default: "Prontas para salvar: \(ready) · Para revisar: \(review)"
        }
    }
}

/// Faixa que sobe do rodapé: um card quadrado pequeno por música da busca, lado a lado, com capa e estado.
/// Botões claros para recolher (o rodapé continua mostrando o progresso) e para limpar a lista.
struct WorkQueuePanel: View {
    @ObservedObject var model: MetadataManagerModel
    let onHide: () -> Void

    var body: some View {
        // Busca pelo índice do modelo (sem varrer a lista inteira por id).
        let rows = model.workRows
        let done = rows.filter { RowLook($0) != .searching && ($0.status != .idle || $0.isDirty) }.count
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text(model.isBusy ? "Buscando" : "Última busca").font(.system(size: 11, weight: .semibold))
                Text("\(done) de \(rows.count)").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Legend()
                Button(action: onHide) { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .help("Recolher (o progresso continua no rodapé)")
                if !model.isBusy {
                    Button { withAnimation(.snappy) { model.clearWork(); onHide() } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help("Fechar e limpar esta lista")
                }
            }
            .padding(.horizontal, 10).frame(height: 26)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(rows) { row in
                        QueueCard(row: row)
                            .onTapGesture { model.selection = [row.id] }
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            }
            .frame(height: 86)
        }
        .background(.background.secondary)
    }
}

/// Card de uma música da busca.
private struct QueueCard: View {
    let row: MetadataRow

    var body: some View {
        let look = RowLook(row)
        VStack(spacing: 3) {
            ZStack(alignment: .topLeading) {
                RowThumb(row: row, size: 44)
                if row.isDirty { FoundDot(visible: true).offset(x: -4, y: -3) }
            }
            Text(row.value("title").isEmpty ? row.fileName : row.value("title"))
                .font(.system(size: 9, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text(caption(look)).font(.system(size: 8)).foregroundStyle(look.color == .yellow ? Color.orange : look.color)
                .lineLimit(1)
        }
        .padding(5)
        .frame(width: 72, height: 78)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(look.color.opacity(look == .searching ? 0.6 : 0.25), lineWidth: 1))
        .help(RowLook.tooltip(row))
        .animation(.snappy, value: look)
    }

    private func caption(_ look: RowLook) -> String {
        switch look {
        case .searching: String(localized: "Buscando…")
        case .complete: String(localized: "Completa")
        case .incomplete: row.isDirty ? String(localized: "Falta salvar") : String(localized: "Incompleta")
        case .review: String(localized: "Revisar")
        case .notFound: String(localized: "Nada")
        case .failed: String(localized: "Erro")
        }
    }
}

/// Legenda das cores dos selos.
struct Legend: View {
    var body: some View {
        HStack(spacing: 10) {
            item(.green, "checkmark", "Completa")
            item(.yellow, "exclamationmark", "Falta algo")
            item(.orange, "questionmark", "Revisar")
            item(.red, "minus", "Nada encontrado")
            HStack(spacing: 3) { FoundDot(visible: true); Text("Encontrado, falta salvar") }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func item(_ color: Color, _ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 6, weight: .black))
                .foregroundStyle(color == .yellow ? Color.black.opacity(0.75) : .white)
                .frame(width: 10, height: 10).background(Circle().fill(color))
            Text(text)
        }
    }
}

/// Resumo ao terminar a busca: o que veio completo, o que veio pela metade (e o que faltou), o que não veio.
struct SearchReportView: View {
    let report: SearchReport
    @ObservedObject var model: MetadataManagerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: report.notFound.isEmpty && report.partial.isEmpty ? "checkmark.seal.fill" : "list.bullet.clipboard")
                    .font(.system(size: 26)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Busca concluída").font(.title3.weight(.semibold))
                    Text("\(report.total) músicas verificadas").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                stat("\(report.complete)", "completas", .green)
                stat("\(report.partial.count)", "parciais", .yellow)
                stat("\(report.notFound.count)", "sem resultado", .red)
                if report.review > 0 { stat("\(report.review)", "para revisar", .orange) }
            }
            if !report.missingTotals.isEmpty {
                Text("O que não foi encontrado: \(report.missingTotals.map { "\($0.0) (\($0.1))" }.joined(separator: " · "))")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if !report.partial.isEmpty || !report.notFound.isEmpty {
                List {
                    if !report.partial.isEmpty {
                        Section("Parciais") {
                            ForEach(report.partial) { p in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).lineLimit(1)
                                    Text("Encontrado: \(p.found.joined(separator: ", "))").foregroundStyle(.green)
                                    Text("Faltou: \(p.missing.joined(separator: ", "))").foregroundStyle(.orange)
                                }
                                .font(.system(size: 11))
                            }
                        }
                    }
                    if !report.notFound.isEmpty {
                        Section("Sem resultado") {
                            ForEach(report.notFound, id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(.red) }
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 280)
            }
            HStack {
                Text("Nada foi gravado ainda.").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
                if model.dirtyCount > 0 {
                    Button("Salvar todas (\(model.dirtyCount))") { model.save(onlySelection: false); dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func stat(_ value: String, _ label: LocalizedStringKey, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(color == .yellow ? Color.orange : color)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.1)))
    }
}
