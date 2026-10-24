import AppKit

/// Consentimento para consultas online (regra do projeto: nada sai do Mac sem o usuário aceitar).
/// Perguntado uma vez; a resposta fica salva e pode ser mudada nas Opções.
enum OnlineConsent {
    static let key = "online.consent"
    static let whatIsSent = String(localized: "Para achar dados, capas e letras, o Wineup envia título, artista, álbum e duração das músicas a serviços online de música. O áudio nunca é enviado (só com o AcoustID ligado vai uma impressão digital do som, não o áudio).")

    enum Answer: String { case granted, denied }

    static var answer: Answer? {
        get { UserDefaults.standard.string(forKey: key).flatMap(Answer.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: key) }
    }

    static var isGranted: Bool { answer == .granted }

    /// Para ações que o usuário pediu: pergunta na primeira vez (janela de aviso). true = pode consultar.
    @MainActor static func ensure() -> Bool {
        if let answer { return answer == .granted }
        let alert = NSAlert()
        alert.messageText = String(localized: "Permitir consultas online?")
        alert.informativeText = whatIsSent + "\n\n" + String(localized: "Você pode mudar isso depois nas Opções do gerenciador de metadados.")
        alert.addButton(withTitle: String(localized: "Permitir"))
        alert.addButton(withTitle: String(localized: "Agora não"))
        let granted = alert.runModal() == .alertFirstButtonReturn
        answer = granted ? .granted : .denied
        return granted
    }
}
