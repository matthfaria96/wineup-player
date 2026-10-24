import Foundation
import CryptoKit
import SFBAudioEngine

/// Retrato completo das tags (conhecidas, adicionais e capas) para comparar antes/depois.
public struct TagSnapshot: Sendable, Equatable, Codable {
    public struct PictureInfo: Sendable, Equatable, Codable {
        public var type: Int
        public var byteCount: Int
        public var sha256: String
    }

    public var fields: [String: String]
    public var additional: [String: String]
    public var pictures: [PictureInfo]
    public var duration: Double?

    public static func read(_ url: URL) throws -> TagSnapshot {
        try read(file: AudioFile(readingPropertiesAndMetadataFrom: url))
    }

    /// A partir de um arquivo já aberto (o gerenciador lê tags e propriedades numa abertura só).
    /// `hashPictures: false` pula o SHA-256 das capas (fica vazio) quando só o tamanho interessa;
    /// comparar antes/depois e desfazer precisam do hash.
    public static func read(file: AudioFile, hashPictures: Bool = true) -> TagSnapshot {
        let m = file.metadata
        var f: [String: String] = [:]
        // Vazio equivale a ausente: o SFB devolve "" para campos que o TagLib cria vazios.
        func put(_ k: String, _ v: String?) { if let v, !v.isEmpty { f[k] = v } }
        put("title", m.title); put("artist", m.artist); put("album", m.albumTitle)
        put("albumArtist", m.albumArtist); put("composer", m.composer); put("genre", m.genre)
        put("year", m.releaseDate); put("lyrics", m.lyrics); put("comment", m.comment)
        put("grouping", m.grouping); put("isrc", m.isrc)
        put("trackNumber", m.trackNumber.map(String.init)); put("trackTotal", m.trackTotal.map(String.init))
        put("discNumber", m.discNumber.map(String.init)); put("discTotal", m.discTotal.map(String.init))
        put("bpm", m.bpm.map(String.init)); put("rating", m.rating.map(String.init))
        put("compilation", m.isCompilation.map { $0 ? "1" : "0" })

        var extra: [String: String] = [:]
        for (k, v) in m.additionalMetadata ?? [:] {
            if let key = k as? String { extra[key] = "\(v)" }
        }
        let pics = m.attachedPictures.map { p -> PictureInfo in
            let digest = hashPictures ? SHA256.hash(data: p.imageData).map { String(format: "%02x", $0) }.joined() : ""
            return PictureInfo(type: Int(p.type.rawValue), byteCount: p.imageData.count, sha256: digest)
        }.sorted { ($0.type, $0.sha256) < ($1.type, $1.sha256) }
        return TagSnapshot(fields: f, additional: extra, pictures: pics, duration: file.properties.duration)
    }

    /// Nomes dos campos que diferem (`additional.<chave>`, `pictures`, `duration`).
    public func differences(from other: TagSnapshot, durationTolerance: Double = 0.05) -> [String] {
        var out: [String] = []
        for k in Set(fields.keys).union(other.fields.keys) where fields[k] != other.fields[k] { out.append(k) }
        for k in Set(additional.keys).union(other.additional.keys) where additional[k] != other.additional[k] {
            out.append("additional.\(k)")
        }
        if pictures != other.pictures { out.append("pictures") }
        if let a = duration, let b = other.duration {
            if abs(a - b) > durationTolerance { out.append("duration") }
        } else if duration != other.duration { out.append("duration") }
        return out.sorted()
    }
}
