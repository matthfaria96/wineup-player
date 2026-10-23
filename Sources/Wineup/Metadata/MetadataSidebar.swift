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
            field("title")
            field("artist")
            field("album")
            HStack(spacing: 8) {
                field("year").frame(width: 70)
                field("trackNumber").frame(width: 56)
                field("genre")
            }
            field("comment")
            field("albumArtist")
            field("composer")
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
        HStack {
            Button("Desfazer") { model.revertSelection() }
                .disabled(!model.selectedRows.contains(where: \.isDirty))
            Spacer()
            Button("Salvar seleção") { model.save(onlySelection: true) }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(!model.selectedRows.contains(where: \.isDirty) || model.isBusy)
        }
        .padding(.top, 4)
    }
}

/// Letra: a nova (pendente) ou a atual do .lrc; busca e escolha manual no catálogo online.
struct LyricsBox: View {
    @ObservedObject var model: MetadataManagerModel
    let row: MetadataRow
    @State private var options: [LyricsCandidate] = []
    @State private var searching = false
    @State private var current: String?
    @State private var showViewer = false
    @State private var editing = false
    @State private var draft = ""

    /// Letras disponíveis para ver, a nova primeiro.
    private var sources: [LyricsSource] {
        var out: [LyricsSource] = []
        if let text = row.lyrics?.text { out.append(LyricsSource(id: "new", title: "Nova", text: text)) }
        if let current { out.append(LyricsSource(id: "lrc", title: "Atual (.lrc)", text: current)) }
        let embedded = row.file.value("lyrics")
        if !embedded.isEmpty { out.append(LyricsSource(id: "tag", title: "Embutida", text: embedded)) }
        return out
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if let first = sources.first {
                    let info = LyricsInfo(first.text)
                    HStack(spacing: 6) {
                        Text(first.title).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(first.id == "new" ? Color.accentColor : .secondary)
                        LyricsKindBadge(info: info)
                    }
                    Text(info.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if first.id == "new", row.file.hasSidecarLyrics {
                        Text("Vai substituir o .lrc atual ao salvar.").font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    Button { showViewer = true } label: {
                        Label("Abrir visualizador", systemImage: "music.note.list")
                    }
                    .controlSize(.small)
                    .help("Tocar a música e ver a letra acompanhando")
                } else {
                    Text("Sem letra.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack {
                    Button(searching ? "Buscando…" : "Buscar letras") { search() }.disabled(searching)
                    Button(editing ? "Cancelar edição" : "Escrever à mão") {
                        draft = sources.first?.text ?? ""
                        withAnimation(.snappy) { editing.toggle() }
                    }
                    if row.lyrics != nil { Button("Descartar nova") { model.setLyrics(nil, for: row.id) } }
                }
                .controlSize(.small)
                if editing {
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: $draft)
                            .font(.system(size: 12))
                            .frame(minHeight: 160)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                        Text("Uma linha por verso. Com marcas como [01:23.45] no início, vira letra sincronizada.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            Button("Usar esta letra") {
                                model.setManualLyrics(draft, for: row.id)
                                withAnimation(.snappy) { editing = false }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .controlSize(.small)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                ForEach(options) { option in
                    Button { model.setLyrics(option, for: row.id) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.isSynced ? "clock.fill" : "text.alignleft")
                                .foregroundStyle(option.isSynced ? Color.green : Color.orange)
                            Text("\(option.title) · \(option.artist)").lineLimit(1)
                            Spacer()
                            Text(option.isSynced ? "sincronizada" : option.instrumental ? "instrumental" : "estática")
                                .foregroundStyle(.secondary)
                            Text(option.duration.map { Self.time($0) } ?? "").monospacedDigit()
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .disabled(option.text == nil)
                    .help(option.isSynced ? "Com marcas de tempo: acompanha a música" : "Sem marcas de tempo")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Letra").font(.system(size: 11, weight: .semibold))
        }
        .task(id: "\(row.id)|\(row.file.hasSidecarLyrics)|\(row.status == .saved)") {
            options = []
            current = row.file.hasSidecarLyrics ? try? String(contentsOf: row.file.lyricsURL, encoding: .utf8) : nil
        }
        .sheet(isPresented: $showViewer) {
            LyricsViewer(fileURL: row.url, songTitle: [row.value("artist"), row.value("title")]
                            .filter { !$0.isEmpty }.joined(separator: " – "),
                         sources: sources, onWillPlay: { model.pauseMainPlayback?() })
        }
    }

    private func search() {
        searching = true
        Task {
            options = Array(await model.lyricsOptions(for: row).prefix(8))
            searching = false
            if options.isEmpty { model.message = "Não encontramos letra para esta faixa." }
        }
    }

    static func time(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// Sem seleção: o que a análise encontrou na pasta, com atalho para filtrar.
struct CollectionSummary: View {
    @ObservedObject var model: MetadataManagerModel

    private func count(_ issue: FixerIssue) -> Int { model.rows.filter { $0.openIssues.contains(issue) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Análise da pasta").font(.system(size: 13, weight: .semibold))
            if model.rows.isEmpty {
                Text(model.isLoading ? "Lendo as músicas…" : "Nenhuma música carregada.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                    ForEach(FixerIssue.allCases, id: \.self) { issue in
                        let n = count(issue)
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
                    if count(.duplicate) > 0 { Button("Duplicadas") { model.filter = .duplicates } }
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
    @State private var targeted = false

    private var single: MetadataRow? { model.selectedRows.count == 1 ? model.selectedRows.first : nil }
    private var pending: CoverImage? {
        let covers = model.selectedRows.map(\.cover)
        guard let first = covers.first, covers.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                cover
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
                Button { model.searchSelection(data: tab == .general, lyrics: tab == .lyrics) } label: {
                    Label(model.isBusy ? "Buscando…" : tab == .lyrics ? "Buscar letra" : "Buscar dados",
                          systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
                .help(tab == .lyrics ? "Procura a letra da seleção" : "Procura título, artista, álbum, capa e demais dados da seleção")
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .animation(.snappy, value: single?.status)
        .task(id: model.selection) { await loadEmbedded() }
    }

    private var cover: some View {
        let image = pending.flatMap { NSImage(data: $0.data) } ?? embedded
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

    private func loadEmbedded() async {
        embedded = nil
        guard let row = single, row.file.hasCover else { return }
        let url = row.url
        let data = await Task.detached { FolderAnalyzer.embeddedCover(url) }.value
        withAnimation(.snappy) { embedded = data.flatMap(NSImage.init(data:)) }
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
