import AppKit
import SwiftUI

/// Escolha guardada para "Vídeos Personalizados": uma animação ("scene:aurora") ou uma categoria ("video:cidades").
enum MotionChoice {
    static let key = "artwork.motion"

    static func label(_ raw: String) -> String? {
        if raw.hasPrefix("scene:"), let m = VisualMode(rawValue: String(raw.dropFirst(6))) { return m.title }
        if raw.hasPrefix("video:") { return VideoCategoryStore.shared.category(String(raw.dropFirst(6)))?.name }
        return nil
    }
}

/// Popover do painel da capa: Capa da Música, Arte da Skin e Vídeos Personalizados (com o escolhido
/// como subtítulo e um botão de configurar ao lado).
struct VisualPicker: View {
    @Binding var modeRaw: String
    @Binding var videoCategory: String
    let hasSkinArt: Bool
    let onConfigure: () -> Void
    @AppStorage(MotionChoice.key) private var motion = ""
    @Environment(\.dismiss) private var dismiss

    private var mode: VisualMode { VisualMode(rawValue: modeRaw) ?? .cover }
    private var isMotion: Bool { ![.cover, .skinArt].contains(mode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("Capa da Música", nil, "photo", selected: mode == .cover) { modeRaw = VisualMode.cover.rawValue; dismiss() }
            row("Arte da Skin", hasSkinArt ? nil : "Esta skin não tem arte", "paintpalette", selected: mode == .skinArt) {
                modeRaw = VisualMode.skinArt.rawValue; dismiss()
            }
            Divider().padding(.vertical, 4)
            HStack(spacing: 4) {
                row("Vídeos Personalizados", MotionChoice.label(motion) ?? "Nenhum selecionado", "film", selected: isMotion) {
                    // Primeira vez (nada escolhido): abre a configuração. Depois: usa o escolhido.
                    if MotionChoice.label(motion) == nil { dismiss(); onConfigure() } else { apply(); dismiss() }
                }
                Button { dismiss(); onConfigure() } label: { Image(systemName: "gearshape").frame(width: 26, height: 26) }
                    .buttonStyle(.borderless)
                    .help("Escolher animação ou vídeo")
                    .accessibilityLabel("Configurar vídeos personalizados")
            }
        }
        .padding(8)
        .frame(width: 290)
    }

    private func apply() {
        if motion.hasPrefix("scene:") { modeRaw = String(motion.dropFirst(6)) }
        else if motion.hasPrefix("video:") { videoCategory = String(motion.dropFirst(6)); modeRaw = VisualMode.videos.rawValue }
    }

    private func row(_ title: String, _ subtitle: String?, _ symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.12) : .clear))
    }
}

/// Configuração dos Vídeos Personalizados: animações (oficiais) e vídeos por categoria (oficiais e meus).
/// Clicar numa linha escolhe e aplica. Oficiais não se apagam (só se desligam); as minhas sim.
struct MotionLibraryView: View {
    @Binding var modeRaw: String
    @Binding var videoCategory: String
    @ObservedObject private var store = VideoCategoryStore.shared
    @AppStorage(MotionChoice.key) private var motion = ""
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var confirmDelete: VideoCategory?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vídeos Personalizados").font(.headline)
                    Text("Escolha o que aparece no lugar da capa.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Concluído") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Form {
                Section("Animações") {
                    ForEach([VisualMode.aurora, .fjord, .city, .universe]) { m in
                        choiceRow(id: "scene:\(m.rawValue)", title: m.title, symbol: m.symbol, official: true, detail: "Desenhada pelo app")
                    }
                }
                Section("Vídeos") {
                    ForEach(store.categories.filter(\.builtIn)) { c in videoRow(c) }
                }
                Section {
                    ForEach(store.categories.filter { !$0.builtIn }) { c in videoRow(c) }
                    HStack {
                        TextField("Nova categoria (ex.: Viagens)", text: $newName).textFieldStyle(.roundedBorder)
                        Button("Criar e escolher pasta…") {
                            let name = newName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            let c = store.add(name: name, folder: VideoCategoriesView.pickFolder())
                            newName = ""
                            choose("video:\(c.id)")
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: { Text("Meus vídeos") } footer: {
                    Text("Vídeos MP4 ou MOV de uma pasta sua, sem som, trocando a cada música.")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 600)
        .confirmationDialog("Apagar a categoria “\(confirmDelete?.name ?? "")”?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Apagar", role: .destructive) {
                if let c = confirmDelete { store.remove(c.id); if motion == "video:\(c.id)" { motion = "" } }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Os vídeos na sua pasta não são apagados.") }
    }

    private func choose(_ id: String) {
        motion = id
        if id.hasPrefix("scene:") { modeRaw = String(id.dropFirst(6)) }
        else { videoCategory = String(id.dropFirst(6)); modeRaw = VisualMode.videos.rawValue }
    }

    private func videoRow(_ c: VideoCategory) -> some View {
        let n = c.clips.count
        return choiceRow(id: "video:\(c.id)", title: c.name, symbol: c.symbol, official: c.builtIn,
                         detail: n == 0 ? "Sem vídeos ainda" : "\(n) vídeo\(n == 1 ? "" : "s")", category: c)
    }

    private func choiceRow(id: String, title: String, symbol: String, official: Bool, detail: String,
                           category: VideoCategory? = nil) -> some View {
        let selected = motion == id
        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
                .foregroundStyle(selected ? Color.white : Color.accentColor)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                    if official {
                        Text("Oficial").font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18))).foregroundStyle(Color.accentColor)
                    }
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if let c = category {
                Menu {
                    Button(c.folder == nil ? "Acoplar uma pasta de vídeos…" : "Trocar a pasta…") {
                        if let f = VideoCategoriesView.pickFolder() { var d = c; d.folder = f.path; store.update(d) }
                    }
                    if c.folder != nil { Button("Remover a pasta acoplada") { var d = c; d.folder = nil; store.update(d) } }
                    if !c.builtIn {
                        Divider()
                        Button("Apagar categoria…", role: .destructive) { confirmDelete = c }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }
        .contentShape(Rectangle())
        .onTapGesture { choose(id) }
    }
}
