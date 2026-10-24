import WineupCore
import AppKit
import ImageIO
import WineupCore
import Foundation
import SFBAudioEngine
import WineupLibrary

/// Lê arquivos de áudio (tags e duração) e capas embutidas.
enum TrackLoader {
    struct Cover {
        let image: NSImage
    }

    static var supportedExtensions: Set<String> {
        Set(AudioFile.supportedPathExtensions.map { $0.lowercased() })
    }

    /// Expande pastas recursivamente e mantém só os formatos suportados.
    static func audioURLs(in urls: [URL]) -> [URL] {
        let allowed = supportedExtensions
        var found: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let walker = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                if let walker {
                    for case let item as URL in walker where allowed.contains(item.pathExtension.lowercased()) {
                        found.append(item)
                    }
                }
            } else if allowed.contains(url.pathExtension.lowercased()) {
                found.append(url)
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func tracks(from urls: [URL]) -> [Track] {
        audioURLs(in: urls).map { track(url: $0) }
    }

    static func track(url: URL) -> Track {
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url) else {
            return Track(id: TrackID(stableKey: url.standardizedFileURL.path), artist: String(localized: "Desconhecido"), title: fallbackTitle, duration: 0, mark: nil, url: url)
        }
        let metadata = file.metadata
        return Track(
            id: TrackID(stableKey: url.standardizedFileURL.path),
            artist: nonEmpty(metadata.artist) ?? String(localized: "Desconhecido"),
            title: nonEmpty(metadata.title) ?? fallbackTitle,
            duration: Int((file.properties.duration ?? 0).rounded()),
            mark: nil,
            url: url,
            album: nonEmpty(metadata.albumTitle),
            year: nonEmpty(metadata.releaseDate).map { String($0.prefix(4)) },
            genre: nonEmpty(metadata.genre)
        )
    }

    /// Tags vazias (comuns em arquivos convertidos) contam como ausentes.
    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Miniatura reduzida da capa embutida (decodifica já no tamanho final, sem a imagem inteira).
    /// Capa: a embutida (frontal primeiro); sem ela, a imagem da pasta (cover.jpg, folder.jpg...).
    static func coverData(for url: URL) -> Data? {
        if let file = try? AudioFile(readingPropertiesAndMetadataFrom: url) {
            let pics = file.metadata.attachedPictures
            if let p = pics.first(where: { $0.type == .frontCover }) ?? pics.first { return p.imageData }
        }
        return FolderCover.url(for: url).flatMap { try? Data(contentsOf: $0) }
    }

    static func thumbnail(for url: URL, maxPixel: Int = 160) -> NSImage? {
        guard let data = coverData(for: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decodifica aqui (fora da thread principal), não no primeiro desenho.
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// Capa do Now Playing: reduzida a no máximo 1024 px e já decodificada (capas de 3000 px+ pesavam no desenho).
    static func cover(for url: URL) -> NSImage? {
        thumbnail(for: url, maxPixel: 1024)
    }

    /// Texto da letra: .lrc ao lado do arquivo (mesmo nome) ou letra embutida.
    static func lyricsText(for url: URL) -> String? {
        let sidecar = url.deletingPathExtension().appendingPathExtension("lrc")
        if let data = try? Data(contentsOf: sidecar),
           let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
           !text.isEmpty {
            return text
        }
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url),
              let text = file.metadata.lyrics, !text.isEmpty else { return nil }
        return text
    }

    static func lyrics(for url: URL) -> [String]? {
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url),
              let text = file.metadata.lyrics, !text.isEmpty
        else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map { String($0) }
        return lines.isEmpty ? nil : lines
    }
}
