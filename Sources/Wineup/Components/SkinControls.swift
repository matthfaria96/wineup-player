import AppKit
import SwiftUI
import WineupLibrary

/// Peças de controle "vestidas" pelo skin. Sem skin, ficam no visual padrão (fundo translúcido, borda fina).

/// Fundo de controle: botão do skin em 9 fatias (normal ou ligado), ou o padrão.
struct SkinChrome: ViewModifier {
    var on = false
    var radius: CGFloat = 6
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(on ? theme.buttonTextOn : theme.buttonText)
            .background { background }
    }

    @ViewBuilder private var background: some View {
        if theme.isGlass {
            GlassControlBackground(on: on, radius: radius + 2)
        } else if let art = theme.art, let s = art.nineSlice(on ? (art.manifest.controls.buttonOn ?? art.manifest.controls.button) : art.manifest.controls.button) {
            Image(nsImage: s.image)
                .resizable(capInsets: EdgeInsets(top: s.inset, leading: s.inset, bottom: s.inset, trailing: s.inset), resizingMode: .stretch)
        } else {
            RoundedRectangle(cornerRadius: radius)
                .fill(on ? theme.rowSelection : theme.ink.opacity(theme.isLight ? 0.04 : 0.06))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(theme.panelBorder, lineWidth: 1))
        }
    }
}

extension View {
    func skinChrome(on: Bool = false, radius: CGFloat = 6) -> some View { modifier(SkinChrome(on: on, radius: radius)) }
}

/// Estilo de botão do skin (aperta = estado "ligado").
struct SkinButtonStyle: ButtonStyle {
    var on = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, compact ? 6 : 9)
            .frame(minHeight: 22)
            .skinChrome(on: on || configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Menu com o rótulo dentro da arte de botão do skin (a lista que abre é a do sistema).
struct SkinMenu<Items: View, Label: View>: View {
    var help: LocalizedStringKey = ""
    /// Largura mínima do conteúdo (para alinhar com botões vizinhos do mesmo tamanho).
    var minWidth: CGFloat? = nil
    @ViewBuilder var items: Items
    @ViewBuilder var label: Label
    @Environment(\.theme) private var theme

    var body: some View {
        Menu { items } label: {
            HStack(spacing: 4) {
                label
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.8)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(minWidth: minWidth)
        .tint(theme.buttonText)
        .foregroundStyle(theme.buttonText)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 8)
        .frame(minHeight: 22)
        .skinChrome()
        .help(help)
    }
}

/// Segmentado do skin: cada opção é um botão; a escolhida fica "ligada".
struct SkinSegmented<Value: Hashable, Item: View>: View {
    @Binding var selection: Value
    let options: [Value]
    var width: CGFloat? = nil
    @ViewBuilder var item: (Value) -> Item

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { value in
                Button { selection = value } label: {
                    item(value).frame(width: width).frame(maxHeight: .infinity)
                }
                .buttonStyle(SkinButtonStyle(on: value == selection, compact: true))
                .accessibilityAddTraits(value == selection ? .isSelected : [])
            }
        }
        .fixedSize()
    }
}

/// Campo de texto com a arte do skin.
struct SkinFieldBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.background {
            if theme.isGlass {
                GlassControlBackground(on: false, radius: 8)
            } else if let art = theme.art, let s = art.nineSlice(art.manifest.controls.field) {
                Image(nsImage: s.image)
                    .resizable(capInsets: EdgeInsets(top: s.inset, leading: s.inset, bottom: s.inset, trailing: s.inset), resizingMode: .stretch)
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: 7).fill(theme.isLight ? Color.white : theme.ink.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.panelBorder, lineWidth: 1))
            }
        }
    }
}

extension View {
    func skinField() -> some View { modifier(SkinFieldBackground()) }
}

/// Veste um `Menu` já existente com a arte de botão do skin.
struct SkinMenuChrome: ViewModifier {
    var compact = false
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .tint(theme.buttonText)
            .foregroundStyle(theme.buttonText)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, compact ? 5 : 8)
            .frame(minHeight: 22)
            .skinChrome()
    }
}

extension View {
    func skinMenuChrome(compact: Bool = false) -> some View { modifier(SkinMenuChrome(compact: compact)) }
}
