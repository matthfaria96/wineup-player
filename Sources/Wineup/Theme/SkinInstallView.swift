import AppKit
import SwiftUI
import WineupLibrary

/// "Sobre o skin": prévia, autor, descrição e créditos antes de instalar um .wineupskin aberto pelo Finder.
struct SkinInstallView: View {
    let archive: URL
    let preview: Skin
    let onClose: () -> Void
    @AppStorage("themeID") private var activeID = SkinStore.defaultID
    @State private var error: String?

    var body: some View {
        let m = preview.manifest
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(.title2.weight(.semibold))
                    if !m.author.isEmpty { Text("por \(m.author)").foregroundStyle(.secondary) }
                }
                Spacer()
                Text(archive.lastPathComponent).font(.caption).foregroundStyle(.tertiary)
            }
            SkinPreview(skin: preview).frame(height: 260)
            if !m.description.isEmpty { Text(m.description).fixedSize(horizontal: false, vertical: true) }
            if !m.credits.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Créditos").font(.headline)
                    ForEach(Array(m.credits.enumerated()), id: \.offset) { _, c in
                        Text("\(c.work) — \(c.author) · \(c.license)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            if SkinStore.shared.isInstalled(m.id) {
                Label("Você já tem um skin “\(SkinStore.shared.skin(m.id)?.name ?? m.name)”: este entra como cópia, o seu não é apagado.",
                      systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancelar", action: onClose).keyboardShortcut(.cancelAction)
                Button("Instalar") { install(use: false) }
                Button("Instalar e usar") { install(use: true) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 640)
    }

    private func install(use: Bool) {
        do {
            let skin = try SkinStore.shared.importSkin(from: archive)
            if use { activeID = skin.id }
            onClose()
        } catch {
            self.error = String(localized: "Não foi possível instalar este skin.")
        }
    }
}

/// Mostra a tela "Sobre o skin" numa janela própria (um .wineupskin aberto pelo Finder ou arrastado).
@MainActor
enum SkinInstaller {
    private static var windows: [NSWindow] = []

    static func present(_ archive: URL) {
        do {
            let skin = try SkinStore.shared.inspect(archive)
            let tmp = skin.folder.deletingLastPathComponent()
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = String(localized: "Instalar skin")
            window.isReleasedWhenClosed = false
            let close = { [weak window] in
                window?.close()
                try? FileManager.default.removeItem(at: tmp)
                windows.removeAll { $0 === window }
            }
            window.contentViewController = NSHostingController(
                rootView: SkinInstallView(archive: archive, preview: skin, onClose: close).preferredColorScheme(.dark))
            window.center()
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Este arquivo não é um skin válido do Wineup.")
            alert.informativeText = archive.lastPathComponent
            alert.runModal()
        }
    }
}
