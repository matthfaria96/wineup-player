import SwiftUI
import UniformTypeIdentifiers
import WineupLibrary

/// Editor da seleção (como no Mp3tag): campos, capa e letra. Vale para todas as linhas selecionadas.
struct MetadataSidebar: View {
    @ObservedObject var model: MetadataManagerModel
    /// Aba do painel: "Geral" (campos e capa) ou "Letra". O botão Buscar procura o que a aba mostra.
    enum Tab: String, Sendable { case general, lyrics }
    @AppStorage("metadata.panel.tab") private var tab: Tab = .general

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if model.selection.isEmpty {
                    CollectionSummary(model: model)
                        .transition(.opacity)
                } else {
                    SelectionHeader(model: model, tab: tab)
                    Picker("Mostrar", selection: $tab.animation(.snappy)) {
                        Text("Geral").tag(Tab.general)
                        Text("Letra").tag(Tab.lyrics)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch tab {
                    case .general:
                        VStack(alignment: .leading, spacing: 10) {
                            fields
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    case .lyrics:
                        Group {
                            if model.selection.count == 1, let row = model.selectedRows.first {
                                LyricsBox(model: model, row: row)
                            } else {
                                Text("Selecione uma música só para ver, buscar ou escrever a letra.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    actions
                }
            }
            .padding(12)
            .animation(.snappy, value: model.selection.isEmpty)
        }
        .background(.background.secondary)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Essenciais: os que contam para a música ficar completa.
            field("title")
            field("artist")
            field("album")
            HStack(spacing: 8) {
                field("year").frame(width: 70)
                field("trackNumber").frame(width: 56)
                field("genre")
            }
            HStack(spacing: 6) {
                Text("Mais informações").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase)
                VStack { Divider() }
            }
            .padding(.top, 6)
            .help("Campos opcionais: não contam para a música ficar completa")
            field("albumArtist")
            field("composer")
            field("comment")
            field("discNumber").frame(width: 70)
        }
    }

    private func field(_ name: String) -> some View {
        let common = model.commonValue(name)
        return VStack(alignment: .leading, spacing: 3) {
            Text(MetadataFieldName.label(name) + ":")
                .font(.system(size: 11))
                .foregroundStyle(model.isEditedInSelection(name) ? Color.accentColor : .secondary)
            HStack(spacing: 2) {
                TextField(common == nil ? "‹manter›" : "", text: Binding(
                    get: { common ?? "" },
                    set: { model.set(name, $0) }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                // Como as caixas do Mp3tag: escolher um valor que já existe nas selecionadas, ou limpar.
                Menu {
                    let values = model.distinctValues(name)
                    ForEach(values, id: \.self) { v in Button(v) { model.set(name, v) } }
                    if !values.isEmpty { Divider() }
                    Button("Limpar o campo") { model.set(name, "") }
                } label: { EmptyView() }
                    .menuStyle(.borderlessButton)
                    .frame(width: 16)
                    .help("Valores destas músicas")
            }
        }
    }

    private var actions: some View {
        let dirty = model.selectedRows.contains(where: \.isDirty)
        return HStack {
            Button("Desfazer") { model.revertSelection() }
                .disabled(!dirty)
            Spacer()
            Button("Salvar seleção") { model.save(onlySelection: true) }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(!dirty || model.isBusy)
        }
        .padding(.top, 4)
    }
}

/// Aba Letra: a letra já aberta (com o tempo de cada linha quando sincronizada), etiquetas sobre o .lrc
/// e dois ícones: editar o texto atual e buscar de novo (pede confirmação se já existe letra).
struct LyricsBox: View {
    @ObservedObject var model: MetadataManagerModel
    let row: MetadataRow
    @State private var options: [LyricsCandidate] = []
    /// Música para a qual as opções foram buscadas (clicar numa opção só vale para ela).
    @State private var optionsFor: MetadataRow.ID?
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var lrcText: String?
    /// Música do .lrc carregado: o texto de outra música nunca aparece nesta.
    @State private var lrcFor: MetadataRow.ID?
    @State private var editing = false
    @State private var draft = ""
    @State private var confirmSearch = false
    @State private var parsed = LyricsInfoMemo()

    /// Letra mostrada: a nova (ainda não gravada), senão a do .lrc, senão a embutida no arquivo.
    private var shown: (text: String, origin: String)? {
        if let text = row.lyrics?.text { return (text, "Nova") }
        if lrcFor == row.id, let lrcText, !lrcText.isEmpty { return (lrcText, ".lrc") }
        let embedded = row.file.value("lyrics")
        return embedded.isEmpty ? nil : (embedded, "Embutida")
    }

    var body: some View {
        // Uma análise da letra por desenho (e só quando o texto muda: o memo guarda a última).
        let shown = shown
        let info = shown.map { parsed.info(for: $0.text) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                tags(shown, info)
                Spacer(minLength: 4)
                if editing {
                    iconButton("xmark", "Cancelar a edição") { withAnimation(.snappy) { editing = false } }
                    iconButton("checkmark", "Usar este texto (gravado ao salvar)", prominent: true) {
                        model.setManualLyrics(draft, for: row.id)
                        withAnimation(.snappy) { editing = false }
                    }
                } else {
                    iconButton("pencil", shown == nil ? "Escrever a letra" : "Editar: ajustar a sincronia ou o texto") {
                        draft = shown?.text ?? ""
                        withAnimation(.snappy) { editing = true; options = [] }
                    }
                    iconButton(searching ? "hourglass" : "magnifyingglass", "Buscar a letra de novo na internet") {
                        if shown == nil { search() } else { confirmSearch = true }
                    }
                    .disabled(searching)
                    if row.lyrics != nil {
                        iconButton("arrow.uturn.backward", "Descartar a letra nova e voltar à atual") {
                            withAnimation(.snappy) { model.setLyrics(nil, for: row.id) }
                        }
                    }
                }
            }
            if !options.isEmpty, optionsFor == row.id { results.transition(.move(edge: .top).combined(with: .opacity)) }
            if editing {
                editor.transition(.opacity)
            } else if let info {
                LyricsText(info: info).transition(.opacity)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "quote.bubble").font(.system(size: 24)).foregroundStyle(.tertiary)
                    Text("Esta música não tem letra.").font(.system(size: 12, weight: .medium))
                    Text("Busque na internet (lupa) ou escreva à mão (lápis).").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
        .animation(.snappy, value: shown?.text)
        .confirmationDialog("Buscar a letra de novo?", isPresented: $confirmSearch) {
            Button("Buscar") { search() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(info?.isSynced == true
                 ? "Esta música já tem letra sincronizada. A busca só mostra opções; nada muda até você escolher uma e salvar."
                 : "A busca só mostra opções; nada muda até você escolher uma e salvar.")
        }
        .task(id: "\(row.id)|\(row.file.hasSidecarLyrics)|\(row.status == .saved)") {
            // Outra música (ou o arquivo mudou): a busca de letras da anterior não vale mais.
            searchTask?.cancel()
            searchTask = nil
            searching = false
            options = []
            optionsFor = nil
            editing = false
            let id = row.id
            let url = row.file.lyricsURL
            let has = row.file.hasSidecarLyrics
            let text = has ? await Task.detached { try? String(contentsOf: url, encoding: .utf8) }.value : nil
            guard !Task.isCancelled else { return }
            lrcText = text
            lrcFor = id
        }
        .onDisappear { searchTask?.cancel(); searching = false }
    }

    /// Etiquetas: de onde vem a letra, o tipo e se será gravada.
    @ViewBuilder private func tags(_ shown: (text: String, origin: String)?, _ info: LyricsInfo?) -> some View {
        if let shown, let info {
            HStack(spacing: 4) {
                Tag(text: shown.origin == "Nova" ? "Nova · falta salvar" : shown.origin == ".lrc" ? "Arquivo .lrc" : "Embutida no arquivo",
                    color: shown.origin == "Nova" ? .accentColor : .secondary)
                Tag(text: info.isSynced ? "Sincronizada" : "Sem tempo", color: info.isSynced ? .green : .orange,
                    symbol: info.isSynced ? "clock.fill" : "text.alignleft")
                    .help(info.summary)
            }
            if shown.origin == "Nova", row.file.hasSidecarLyrics {
                Tag(text: "Substitui o .lrc", color: .orange).help("Ao salvar, o .lrc atual é trocado (com backup)")
            } else if shown.origin == "Embutida" {
                Tag(text: "Sem .lrc", color: .secondary).help("A letra está nas tags do arquivo; não há arquivo .lrc ao lado")
            }
        } else {
            Tag(text: "Sem letra", color: .red, symbol: "minus.circle")
        }
    }

    private var editor: some View {
        LyricsSyncEditor(draft: $draft, fileURL: row.url, onWillPlay: { model.pauseMainPlayback?() })
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Escolha uma letra").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { withAnimation(.snappy) { options = [] } } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Fechar a lista")
            }
            ForEach(options) { option in
                Button {
                    if let id = optionsFor, id == row.id { model.setLyrics(option, for: id) }
                    withAnimation(.snappy) { options = [] }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.isSynced ? "clock.fill" : "text.alignleft")
                            .foregroundStyle(option.isSynced ? Color.green : Color.orange)
                        Text("\(option.title) · \(option.artist)").lineLimit(1)
                        Spacer()
                        Text(option.duration.map { Self.time($0) } ?? "").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .padding(.vertical, 3).padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(option.text == nil)
                .help(option.isSynced ? "Sincronizada: acompanha a música" : option.instrumental ? "Instrumental" : "Sem marcas de tempo")
            }
        }
    }

    private func iconButton(_ symbol: String, _ help: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 16, height: 16)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.bordered)
        .tint(prominent ? .accentColor : nil)
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(help)
    }

    private func search() {
        searchTask?.cancel()
        let current = row
        searching = true
        searchTask = Task {
            let found = Array(await model.lyricsOptions(for: current).prefix(8))
            // Trocou de música no meio: as opções seriam aplicadas à música errada.
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { options = found; optionsFor = current.id }
            searching = false
            if found.isEmpty { model.message = "Não encontramos letra para esta faixa." }
        }
    }

    static func time(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// Etiqueta pequena e colorida.
private struct Tag: View {
    let text: String
    let color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
            Text(text)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// A letra na tela: cada verso com o tempo ao lado quando é sincronizada.
private struct LyricsText: View {
    let info: LyricsInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.summary).font(.system(size: 10)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(info.lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let t = line.time {
                                Text(LyricsBox.time(t)).font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                            Text(line.text.isEmpty ? " " : line.text).font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(minHeight: 260, maxHeight: 420)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
        }
    }
}

/// Sem seleção: o que a análise encontrou na pasta, com atalho para filtrar.
struct CollectionSummary: View {
    @ObservedObject var model: MetadataManagerModel

    var body: some View {
        // Uma passada pelas linhas, guardada no modelo até a lista mudar.
        let counts = model.summary
        VStack(alignment: .leading, spacing: 10) {
            Text("Análise da pasta").font(.system(size: 13, weight: .semibold))
            if model.rows.isEmpty {
                Text(model.isLoading ? "Lendo as músicas…" : "Nenhuma música carregada.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                    ForEach(FixerIssue.allCases, id: \.self) { issue in
                        let n = counts.count(issue)
                        GridRow {
                            Text(issue.label)
                            Text("\(n)").monospacedDigit().foregroundStyle(n == 0 ? Color.secondary : .orange)
                                .gridColumnAlignment(.trailing)
                        }
                        .font(.system(size: 12))
                    }
                }
                Divider()
                Text("Corrigir tudo busca metadados, capas e letras sincronizadas para as músicas com problemas. Resultados com confiança alta já entram como alteração; os outros ficam marcados para revisar. Nada é gravado até você salvar.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Para editar à mão, selecione uma ou mais músicas na lista. Clique duas vezes numa música para escolher entre os resultados.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Ver só as com problemas") { model.filter = .problems }
                    if counts.count(.duplicate) > 0 { Button("Duplicadas") { model.filter = .duplicates } }
                }
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }
}

/// Topo do painel: capa (pequena, aceita arrastar uma imagem) com título, artista e estado ao lado,
/// e as ações de enviar capa e buscar.
struct SelectionHeader: View {
    @ObservedObject var model: MetadataManagerModel
    let tab: MetadataSidebar.Tab
    @State private var embedded: NSImage?
    /// Capa nova (pendente) já reduzida fora da thread principal.
    @State private var pendingImage: NSImage?
    @State private var targeted = false
    /// Lado da miniatura em pixels (84 pt em tela Retina).
    private static let coverPixels = 168

    private var single: MetadataRow? {
        let selected = model.selectedRows
        return selected.count == 1 ? selected.first : nil
    }
    private var pending: CoverImage? {
        let covers = model.selectedRows.map(\.cover)
        guard let first = covers.first, covers.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    var body: some View {
        let single = single
        let pending = pending
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                cover(pending: pending)
                VStack(alignment: .leading, spacing: 3) {
                    if let row = single {
                        Text(row.value("title").isEmpty ? row.fileName : row.value("title"))
                            .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        Text([row.value("artist"), row.value("album")].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        HStack(spacing: 5) {
                            StatusBadge(row: row, size: 12)
                            Text(status(row)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.top, 2)
                        if let c = row.confidence { ConfidenceChip(value: c).padding(.top, 1) }
                    } else {
                        Text("\(model.selection.count) músicas").font(.system(size: 13, weight: .semibold))
                        Text("Os campos e a capa valem para todas as selecionadas.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Button { model.chooseCoverFile() } label: { Label("Enviar capa", systemImage: "photo.badge.plus") }
                    .help("Escolher uma imagem (JPEG ou PNG). Também dá para arrastar uma imagem para a capa.")
                if pending != nil {
                    Button("Manter a atual") { model.setCover(nil) }
                }
                Spacer(minLength: 0)
                if tab == .general || single == nil {
                    Button { model.searchSelection(data: tab == .general, lyrics: tab == .lyrics) } label: {
                        Label(model.isBusy ? "Buscando…" : tab == .lyrics ? "Buscar letras" : "Buscar dados",
                              systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                    .help(tab == .lyrics ? "Procura a letra das selecionadas" : "Procura título, artista, álbum, capa e demais dados da seleção")
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .animation(.snappy, value: single?.status)
        .task(id: model.selection) { await loadEmbedded(single) }
        .task(id: pending) { await loadPending(pending) }
    }

    private func cover(pending: CoverImage?) -> some View {
        let image = pending == nil ? embedded : (pendingImage ?? embedded)
        return ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(targeted ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: targeted ? 2 : 1))
        .overlay(alignment: .bottomTrailing) {
            if pending != nil {
                Text("Nova").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor)).padding(4)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .scaleEffect(targeted ? 1.05 : 1)
        .animation(.snappy, value: targeted)
        .help(pending != nil ? "Nova capa: será gravada ao salvar" : "Arraste uma imagem para trocar a capa")
        .onDrop(of: [.fileURL, .image], isTargeted: $targeted) { providers in load(providers); return true }
    }

    private func status(_ row: MetadataRow) -> String {
        switch RowLook(row) {
        case .searching: "Buscando…"
        case .complete: "Completa"
        case .incomplete: row.isDirty ? "Encontrado: \(row.foundItems.joined(separator: ", ")) · falta salvar"
            : "Falta: " + row.missingEssentials.joined(separator: ", ")
        case .review: "Encontrada com pouca confiança"
        case .notFound: "Nada encontrado nas bases"
        case .failed: row.status.label
        }
    }

    /// Lê e reduz a capa embutida fora da thread principal; descarta se a seleção mudou no meio.
    private func loadEmbedded(_ row: MetadataRow?) async {
        embedded = nil
        guard let row, row.file.hasCover else { return }
        let url = row.url
        let pixels = Self.coverPixels
        let image = await Task.detached(priority: .userInitiated) {
            FolderAnalyzer.embeddedCover(url).flatMap { ThumbnailCache.downsample($0, to: pixels) }
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) { embedded = image }
    }

    private func loadPending(_ cover: CoverImage?) async {
        pendingImage = nil
        guard let cover else { return }
        let decoded = await CoverDecode.decode(cover.data, maxPixels: Self.coverPixels)
        guard !Task.isCancelled else { return }
        pendingImage = decoded?.image
    }

    private func load(_ providers: [NSItemProvider]) {
        guard let p = providers.first else { return }
        if p.canLoadObject(ofClass: URL.self) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                let data = url.flatMap { try? Data(contentsOf: $0) }
                Task { @MainActor in model.setCoverData(data) }
            }
        } else {
            p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                Task { @MainActor in model.setCoverData(data) }
            }
        }
    }
}

/// Guarda a última letra analisada: o mesmo texto não é analisado de novo a cada desenho.
@MainActor
final class LyricsInfoMemo {
    private var last: (text: String, info: LyricsInfo)?

    func info(for text: String) -> LyricsInfo {
        if let last, last.text == text { return last.info }
        let info = LyricsInfo(text)
        last = (text, info)
        return info
    }
}
