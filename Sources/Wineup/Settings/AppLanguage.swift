import AppKit
import Foundation

/// Idioma do app: "Sistema" (segue o macOS) ou um dos idiomas traduzidos.
/// Guarda a escolha em `AppleLanguages` do próprio app; vale a partir da próxima abertura.
enum AppLanguage {
    static let system = "system"

    /// Idiomas com tradução, cada um no próprio nome (como o usuário o reconhece).
    static let supported: [(code: String, name: String)] = [
        ("en", "English (US)"),
        ("pt-BR", "Português (Brasil)"),
        ("es", "Español"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("ru", "Русский"),
        ("uk", "Українська"),
        ("pl", "Polski"),
        ("cs", "Čeština"),
        ("hu", "Magyar"),
        ("nl", "Nederlands"),
        ("sv", "Svenska"),
        ("tr", "Türkçe"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("zh-Hans", "简体中文"),
    ]

    private static let key = "AppleLanguages"

    /// O idioma escolhido no app, ou `system`.
    static var current: String {
        guard let list = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key] as? [String],
              let first = list.first else { return system }
        return supported.contains { $0.code == first } ? first : system
    }

    static func set(_ code: String) {
        if code == system { UserDefaults.standard.removeObject(forKey: key) }
        else { UserDefaults.standard.set([code], forKey: key) }
    }

    /// O idioma que está em uso agora (o carregado ao abrir o app).
    static var active: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// Abre o app de novo, já no idioma escolhido.
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
