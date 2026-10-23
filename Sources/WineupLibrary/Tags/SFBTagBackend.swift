import Foundation
import SFBAudioEngine

/// FLAC, M4A/ALAC, Ogg Opus/Vorbis via SFBAudioEngine.
public struct SFBTagBackend: TagBackend {
    public init() {}

    public func write(_ changes: TagChanges, to url: URL) throws {
        let file = try AudioFile(readingPropertiesAndMetadataFrom: url)
        let m = file.metadata
        if let v = changes.title { m.title = v }
        if let v = changes.artist { m.artist = v }
        if let v = changes.album { m.albumTitle = v }
        if let v = changes.albumArtist { m.albumArtist = v }
        if let v = changes.genre { m.genre = v }
        if let v = changes.year { m.releaseDate = v }
        if let v = changes.trackNumber { m.trackNumber = v }
        if let v = changes.discNumber { m.discNumber = v }
        if let v = changes.composer { m.composer = v }
        if let v = changes.comment { m.comment = v }
        if let cover = changes.cover {
            m.removeAllAttachedPictures()
            m.attachPicture(AttachedPicture(imageData: cover.data, type: .frontCover))
        }
        try file.writeMetadata()
    }
}
