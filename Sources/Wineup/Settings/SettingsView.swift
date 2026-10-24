import SwiftUI

/// Janela de Ajustes (⌘,): repete o que a tela principal oferece, para quem não achar lá.
/// Usa as mesmas preferências e o mesmo `PlayerState`, então mudar aqui muda lá e vice-versa.
struct SettingsView: View {
    @ObservedObject var state: PlayerState
    @Binding var layoutRaw: String
    @Binding var themeID: String
    @AppStorage("settings.tab") private var tabRaw = SettingsTab.general.rawValue

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, sound, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: String(localized: "Geral")
            case .sound: String(localized: "Som")
            case .about: String(localized: "Sobre")
            }
        }
    }

    private var tab: SettingsTab { SettingsTab(rawValue: tabRaw) ?? .general }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Ajustes", selection: $tabRaw) {
                ForEach(SettingsTab.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 14)

            Group {
                switch tab {
                case .general: GeneralSettings(state: state, layoutRaw: $layoutRaw, themeID: $themeID)
                case .sound: SoundSettings(state: state)
                case .about: SettingsPage { AboutView(compact: true).frame(maxWidth: .infinity) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 600)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .preferredColorScheme(.dark)
    }
}
