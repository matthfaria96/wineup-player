import Foundation

public enum TagBackendError: Error, Equatable {
    case unsupportedFormat
    case writeFailed(code: Int32)
}

/// Quem realmente toca os bytes do arquivo. Só o TagWriter deve chamar, sobre a cópia de trabalho.
public protocol TagBackend: Sendable {
    func write(_ changes: TagChanges, to url: URL) throws
}

public enum TagBackends {
    /// MP3/WAV pelo shim TagLib (versão ID3 e datas parciais); demais pelo SFBAudioEngine.
    public static func backend(for url: URL) -> TagBackend? {
        switch url.pathExtension.lowercased() {
        case "mp3", "wav", "wave":
            return ID3TagBackend()
        case "flac", "m4a", "mp4", "aac", "alac", "opus", "ogg", "oga":
            return SFBTagBackend()
        default:
            return nil
        }
    }
}
