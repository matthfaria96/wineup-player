import AppKit
import SwiftUI

/// Janela "Sobre o Wineup Player", no mesmo padrão dos outros apps witchmymac.
struct AboutView: View {
    @StateObject private var sheet = AboutSheetState()

    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Versão \(marketing) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.bottom, 18)
            Text("Wineup Player")
                .font(.system(size: 24, weight: .semibold))
            Text(version)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)

            Text("O Wineup Player toca sua biblioteca de música com a cara dos players clássicos: FLAC, MP3, Ogg, Opus, APE e outros formatos, com equalizador, letras, capa e playlist em painéis que você organiza.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 460)
                .padding(.top, 26)

            Text("O Wineup Player é software livre sob a GNU GPL v3.0. Ele se apoia nos projetos de código aberto listados nas suas licenças.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 14)

            HStack(spacing: 18) {
                Link("witchmymac.com", destination: URL(string: "http://witchmymac.com")!)
                    .font(.system(size: 12))
                Button("Licenças de código aberto") { sheet.showLicenses = true }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            .padding(.top, 10)
        }
        .frame(width: 540)
        .padding(.top, 36)
        .padding(.bottom, 32)
        .sheet(isPresented: $sheet.showLicenses) { OpenSourceLicensesView() }
    }
}

private final class AboutSheetState: ObservableObject {
    @Published var showLicenses = false
}
