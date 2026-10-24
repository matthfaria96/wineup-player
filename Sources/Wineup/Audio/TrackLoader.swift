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

    /// Leituras de tags ao mesmo tempo (o TagLib bloqueia a thread; mais que isso só disputa o disco).
    static let maxConcurrentReads = 6

    /// Lê as faixas com até `width` leituras simultâneas, fora da thread principal, e entrega na ordem dos
    /// arquivos em lotes crescentes (`LoadBatches`): a lista aparece com os primeiros sem esperar os 5 mil.
    static func trackBatches(_ urls: [URL], width: Int = maxConcurrentReads) -> AsyncStream<[Track]> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: (Int, Track).self) { group in
                    var ready = [Track?](repeating: nil, count: urls.count)
                    var next = 0, delivered = 0
                    while next < min(max(1, width), urls.count) {
                        let (i, url) = (next, urls[next])
                        group.addTask { (i, track(url: url)) }
                        next += 1
                    }
                    for await (i, track) in group {
                        if Task.isCancelled { group.cancelAll(); break }
                        ready[i] = track
                        if next < urls.count {
                            let (j, url) = (next, urls[next])
                            group.addTask { (j, Self.track(url: url)) }
                            next += 1
                        }
                        // Entrega só o trecho contínuo já lido (a ordem da lista não muda depois).
                        var end = delivered
                        while end < urls.count, ready[end] != nil { end += 1 }
                        if end - delivered >= LoadBatches.size(afterDelivered: delivered) || end == urls.count, end > delivered {
                            continuation.yield(ready[delivered..<end].compactMap { $0 })
                            delivered = end
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
        embeddedCoverData(for: url) ?? FolderCover.url(for: url).flatMap { try? Data(contentsOf: $0) }
    }

    /// Só a capa embutida no arquivo (frontal primeiro).
    static func embeddedCoverData(for url: URL) -> Data? {
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url) else { return nil }
        let pics = file.metadata.attachedPictures
        return (pics.first(where: { $0.type == .frontCover }) ?? pics.first)?.imageData
    }

    static func thumbnail(for url: URL, maxPixel: Int = 160) -> NSImage? {
        coverData(for: url).flatMap { thumbnail(data: $0, maxPixel: maxPixel) }
    }

    /// Miniatura a partir dos bytes da imagem.
    static func thumbnail(data: Data, maxPixel: Int = 160) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
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
