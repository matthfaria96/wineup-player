import SwiftUI

/// Peças da janela de Ajustes, no jeito dos Ajustes do Sistema (e do MacDash): grupos de linhas sobre o
/// fundo, texto à esquerda, controle nativo à direita e as explicações como rodapé discreto.
enum SettingsStyle {
    static let columnWidth: CGFloat = 560
    static let sectionSpacing: CGFloat = 24
    static let corner: CGFloat = 10
    static let rowFill = Color.white.opacity(0.055)
    static let rowStroke = Color.white.opacity(0.06)
    static let separator = Color.white.opacity(0.08)
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.5)
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
    let title: String
    var footer: String?
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
    let title: String
    var detail: String?
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
