import Foundation
import ShazamKit

/// Reconhecimento pelo catálogo do Shazam (ShazamKit).
/// A Apple só atende apps assinados com uma conta de desenvolvedor que tenha o serviço ShazamKit;
/// sem isso o serviço responde "Missing entitlements" e o reconhecedor se desliga até o app reabrir.
public actor ShazamRecognizer {
    public struct Recognition: Sendable, Equatable {
        public let title: String
        public let artist: String
        public let isrc: String?
    }

    public enum Availability: Sendable, Equatable {
        case unknown, available
        case unavailable(String)
    }

    public static let shared = ShazamRecognizer()
    public private(set) var availability: Availability = .unknown

    public func recognize(_ url: URL) async throws -> Recognition? {
        if case .unavailable = availability { return nil }
        guard let buffer = try AudioExcerpt.read(url) else { return nil }
        let generator = SHSignatureGenerator()
        try generator.append(buffer, at: nil)
        let result = await SHSession().result(from: generator.signature())
        return try handle(result)
    }

    private func handle(_ result: SHSession.Result) throws -> Recognition? {
        switch result {
        case .match(let match):
            availability = .available
            guard let item = match.mediaItems.first, let title = item.title, let artist = item.artist else { return nil }
            return Recognition(title: title, artist: artist, isrc: item.isrc)
        case .noMatch:
            availability = .available
            return nil
        case .error(let error, _):
            if Self.isEntitlementError(error) {
                availability = .unavailable("O Shazam exige o app assinado com o serviço ShazamKit (conta Apple Developer).")
                return nil
            }
            throw error
        @unknown default:
            return nil
        }
    }

    /// "Missing entitlements" (ShazamKit 202), "enable the ShazamKit App Service" (ShazamCore 102)
    /// ou 401 do serviço por baixo: o app não tem permissão de usar o catálogo.
    static func isEntitlementError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let e = current {
            let text = "\(e.localizedDescription) \(e.userInfo[NSDebugDescriptionErrorKey] ?? "")".lowercased()
            if (e.domain == SHErrorDomain && e.code == 202) || text.contains("entitlement")
                || text.contains("app service") || e.userInfo["AMSStatusCode"] as? Int == 401 { return true }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
