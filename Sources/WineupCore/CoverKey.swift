import Foundation

/// Chaves do cache de capas por álbum: faixas do mesmo álbum na mesma pasta dividem uma miniatura.
public enum CoverKey {
    /// Capa vinda de imagem solta: a chave é a pasta da imagem.
    public static func folder(_ folderPath: String) -> String {
        "folder:" + normalized(folderPath)
    }

    /// Capa de um álbum numa pasta (nil sem nome de álbum ou com nome vazio).
    public static func album(folderPath: String, album: String?) -> String? {
        guard let name = album?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return "album:" + normalized(folderPath) + "\n" + name.lowercased()
    }

    /// Chave de álbum a partir do arquivo de áudio (pasta do arquivo + álbum).
    public static func album(for audio: URL, album: String?) -> String? {
        Self.album(folderPath: audio.deletingLastPathComponent().path, album: album)
    }

    /// Pasta sem barra final e com "." e ".." resolvidos.
    private static func normalized(_ path: String) -> String {
        let standard = URL(fileURLWithPath: path).standardizedFileURL.path
        return standard.count > 1 && standard.hasSuffix("/") ? String(standard.dropLast()) : standard
    }
}
