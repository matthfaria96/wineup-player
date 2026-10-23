import Foundation
import WineupID3

/// MP3 e WAV via shim TagLib: mantém versão ID3, frames desconhecidos e não cria ID3v1.
public struct ID3TagBackend: TagBackend {
    public init() {}

    public func write(_ changes: TagChanges, to url: URL) throws {
        let code = Self.withOptionalCString(changes.title) { title in
            Self.withOptionalCString(changes.artist) { artist in
                Self.withOptionalCString(changes.album) { album in
                    Self.withOptionalCString(changes.albumArtist) { albumArtist in
                        Self.withOptionalCString(changes.genre) { genre in
                            Self.withOptionalCString(changes.year) { year in
                                Self.withOptionalCString(changes.composer) { composer in
                                    Self.withOptionalCString(changes.comment) { comment in
                                        Self.withCover(changes.cover) { bytes, count, mime in
                                            url.path.withCString { path in
                                                wid3_write(path, title, artist, album, albumArtist, genre, year,
                                                           Int32(changes.trackNumber ?? 0),
                                                           Int32(changes.discNumber ?? 0),
                                                           composer, comment, bytes, count, mime)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if code != 0 { throw TagBackendError.writeFailed(code: code) }
    }

    private static func withCover<R>(_ cover: CoverImage?,
                                     _ body: (UnsafePointer<UInt8>?, Int, UnsafePointer<CChar>?) -> R) -> R {
        guard let cover, !cover.data.isEmpty else { return body(nil, 0, nil) }
        return cover.data.withUnsafeBytes { raw in
            cover.mimeType.withCString { mime in
                body(raw.bindMemory(to: UInt8.self).baseAddress, cover.data.count, mime)
            }
        }
    }

    private static func withOptionalCString<R>(_ s: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
        guard let s else { return body(nil) }
        return s.withCString { body($0) }
    }
}
