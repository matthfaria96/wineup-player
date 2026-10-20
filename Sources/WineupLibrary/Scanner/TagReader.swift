import Foundation
import SFBAudioEngine

/// Leitura de tags via SFBAudioEngine para um valor Sendable (nunca guarda imagens).
public enum TagReader {
    /// Mesma lista de extensões que o app aceita (TrackLoader).
    public static let audioExtensions: Set<String> =
        Set(AudioFile.supportedPathExtensions.map { $0.lowercased() })

    public static func read(_ url: URL) throws -> ScannedTags {
        let file = try AudioFile(readingPropertiesAndMetadataFrom: url)
        let m = file.metadata
        var releaseType: String?
        if let extra = m.additionalMetadata {
            for key in ["RELEASETYPE", "MusicBrainz Album Type"] {
                if let v = extra[key] as? String, !v.isEmpty { releaseType = v; break }
            }
        }
        return ScannedTags(
            title: m.title, artist: m.artist, albumArtist: m.albumArtist,
            album: m.albumTitle, genre: m.genre,
            year: m.releaseDate.map { String($0.prefix(4)) },
            releaseType: releaseType,
            trackNumber: m.trackNumber, discNumber: m.discNumber,
            duration: file.properties.duration,
            hasEmbeddedArtwork: !m.attachedPictures.isEmpty,
            lyrics: m.lyrics)
    }
}
