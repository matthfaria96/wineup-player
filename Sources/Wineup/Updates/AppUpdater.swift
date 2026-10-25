import AppKit
import Combine
import Sparkle
import SwiftUI

/// Atualizações dentro do app pelo Sparkle, como no Sirena. O feed (SUFeedURL), a chave pública EdDSA
/// (SUPublicEDKey) e a verificação diária ficam no Info.plist (scripts/build-app.sh). As versões são
/// assinadas com a chave EdDSA do witchmymac e o app com o certificado witchmymac.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    /// Falso enquanto uma verificação ou instalação já está em andamento.
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    private init() {}

    /// Liga o agendador do Sparkle (verificação diária). Uma vez, ao abrir o app.
    /// Cópias de teste (outro bundle id) não verificam, a não ser com WINEUP_UPDATES=1.
    func start() {
        guard controller == nil else { return }
        let env = ProcessInfo.processInfo.environment
        guard Bundle.main.bundleIdentifier == "app.wineup.player" || env["WINEUP_UPDATES"] != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            DispatchQueue.main.async { self?.canCheckForUpdates = canCheck }
        }
        controller.startUpdater()
    }

    /// "Verificar Atualizações…": sempre mostra um resultado, mesmo "Você já está atualizado".
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// Item do menu do app e botão do Sobre: desabilitado enquanto já há uma verificação em andamento.
struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Button("Verificar Atualizações…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
