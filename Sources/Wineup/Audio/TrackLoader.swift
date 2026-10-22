import WineupCore
import AppKit
import WineupCore
import Foundation
import SFBAudioEngine

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
            return Track(id: TrackID(stableKey: url.standardizedFileURL.path), artist: "Desconhecido", title: fallbackTitle, duration: 0, mark: nil, url: url)
        }
        let metadata = file.metadata
        return Track(
            id: TrackID(stableKey: url.standardizedFileURL.path),
            artist: nonEmpty(metadata.artist) ?? "Desconhecido",
            title: nonEmpty(metadata.title) ?? fallbackTitle,
            duration: Int((file.properties.duration ?? 0).rounded()),
            mark: nil,
            url: url,
            album: nonEmpty(metadata.albumTitle),
            year: nonEmpty(metadata.releaseDate).map { String($0.prefix(4)) }
        )
    }

    /// Tags vazias (comuns em arquivos convertidos) contam como ausentes.
    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func cover(for url: URL) -> NSImage? {
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url),
              let picture = file.metadata.attachedPictures.first
        else { return nil }
        return NSImage(data: picture.imageData)
    }

    static func lyrics(for url: URL) -> [String]? {
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url),
              let text = file.metadata.lyrics, !text.isEmpty
        else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map { String($0) }
        return lines.isEmpty ? nil : lines
    }
}
