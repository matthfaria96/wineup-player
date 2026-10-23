import Foundation

/// Capa como imagem solta na pasta do álbum (cover.jpg, folder.png, front.jpg...).
/// Só para exibir: nunca grava nada no arquivo de áudio.
public enum FolderCover {
    static let names = ["cover", "folder", "front", "album", "albumart", "albumartlarge", "capa", "artwork"]
    static let extensions = ["jpg", "jpeg", "png", "webp", "heic", "gif", "bmp"]

    private static let cache = NSCache<NSString, NSURL>()
    private static let none = NSURL(fileURLWithPath: "/dev/null")

    /// Imagem da pasta da música: primeiro pelos nomes conhecidos; senão, a única imagem da pasta.
    public static func url(for audio: URL) -> URL? {
        let folder = audio.deletingLastPathComponent()
        let key = folder.path as NSString
        if let hit = cache.object(forKey: key) { return hit == none ? nil : hit as URL }
        let found = find(in: folder)
        cache.setObject((found as NSURL?) ?? none, forKey: key)
        return found
    }

    public static func invalidate(_ folder: URL) { cache.removeObject(forKey: folder.path as NSString) }

    static func find(in folder: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        let images = items.filter { extensions.contains($0.pathExtension.lowercased()) }
        for name in names {
            if let match = images.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == name }) {
                return match
            }
        }
        return images.count == 1 ? images[0] : nil
    }
}

/// Liga/desliga cada serviço online (além do consentimento geral).
public enum OnlineServices {
    public enum Service: String, CaseIterable, Sendable {
        case metadata, albumHint, lyrics

        public var title: String {
            switch self {
            case .metadata: "Dados e capas de álbuns (MusicBrainz e Cover Art Archive)"
            case .albumHint: "Descobrir o álbum e capas extras (busca do iTunes)"
            case .lyrics: "Letras"
            }
        }

        var key: String { "online.service.\(rawValue)" }
    }

    public static func isOn(_ s: Service) -> Bool {
        UserDefaults.standard.object(forKey: s.key) as? Bool ?? true
    }

    public static func set(_ s: Service, _ on: Bool) { UserDefaults.standard.set(on, forKey: s.key) }
}
