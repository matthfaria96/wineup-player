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
