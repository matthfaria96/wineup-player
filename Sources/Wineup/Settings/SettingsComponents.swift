import AppKit
import SwiftUI

/// Peças da janela de Ajustes, no jeito dos Ajustes do Sistema (e do MacDash): grupos de linhas sobre o
/// fundo, texto à esquerda, controle nativo à direita e as explicações como rodapé discreto.
enum SettingsStyle {
    static let columnWidth: CGFloat = 560
    static let sectionSpacing: CGFloat = 24
    static let corner: CGFloat = 10
    // Claro só com o tema Glass claro; o escuro é o de sempre.
    static let rowFill = Color.adaptive(dark: .white.withAlphaComponent(0.055), light: .white.withAlphaComponent(0.75))
    static let rowStroke = Color.adaptive(dark: .white.withAlphaComponent(0.06), light: .black.withAlphaComponent(0.07))
    static let separator = Color.adaptive(dark: .white.withAlphaComponent(0.08), light: .black.withAlphaComponent(0.08))
    static let primary = Color.adaptive(dark: .white.withAlphaComponent(0.92), light: .black.withAlphaComponent(0.88))
    static let secondary = Color.adaptive(dark: .white.withAlphaComponent(0.5), light: .black.withAlphaComponent(0.5))
    static let background = Color.adaptive(dark: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
                                           light: NSColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1))
}

/// Coluna rolável de seções, centralizada.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsStyle.sectionSpacing) { content }
                .frame(maxWidth: SettingsStyle.columnWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
    }
}

/// Grupo de linhas com título e rodapé opcional.
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SettingsStyle.primary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(SettingsStyle.rowFill, in: RoundedRectangle(cornerRadius: SettingsStyle.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: SettingsStyle.corner, style: .continuous)
                    .strokeBorder(SettingsStyle.rowStroke, lineWidth: 0.5))
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SettingsStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Uma linha: o que é (com uma frase de explicação) à esquerda, o controle à direita.
struct SettingsRow<Control: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    var symbol: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(SettingsStyle.secondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsStyle.primary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(SettingsStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
    }
}

/// Linha fina entre linhas de um grupo.
struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(SettingsStyle.separator)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
}

extension View {
    func settingsSwitch() -> some View { labelsHidden().toggleStyle(.switch).controlSize(.small) }
    func settingsMenu() -> some View { labelsHidden().pickerStyle(.menu).fixedSize() }
}

extension Color {
    /// Cor que muda com o claro/escuro da janela.
    static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}
