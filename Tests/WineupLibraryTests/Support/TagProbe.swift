import Foundation
@testable import WineupLibrary

/// Leitores crus de bytes, independentes do SFB/TagLib, para as asserções de preservação.
enum TagProbe {
    private static func u32le(_ d: Data, _ p: Int) -> Int {
        Int(d[p]) | Int(d[p + 1]) << 8 | Int(d[p + 2]) << 16 | Int(d[p + 3]) << 24
    }
    private static func syncsafe(_ d: Data, _ p: Int) -> Int {
        Int(d[p] & 127) << 21 | Int(d[p + 1] & 127) << 14 | Int(d[p + 2] & 127) << 7 | Int(d[p + 3] & 127)
    }
    private static func be32(_ d: Data, _ p: Int) -> Int {
        Int(d[p]) << 24 | Int(d[p + 1]) << 16 | Int(d[p + 2]) << 8 | Int(d[p + 3])
    }

    /// Início do cabeçalho ID3 (offset 0 no MP3; dentro do chunk "ID3 " no WAV).
    private static func id3Offset(_ d: Data) -> Int? {
        if d.starts(with: Data("ID3".utf8)) { return 0 }
        guard d.starts(with: Data("RIFF".utf8)) else { return nil }
        var p = 12
        while p + 8 <= d.count {
            let id = String(decoding: d[p..<p + 4], as: UTF8.self)
            let size = u32le(d, p + 4)
            if id.lowercased() == "id3 " { return p + 8 }
            p += 8 + size + (size % 2)
        }
        return nil
    }

    static func id3Version(_ url: URL) -> Int? {
        guard let d = try? Data(contentsOf: url), let o = id3Offset(d), d.count > o + 4 else { return nil }
        return Int(d[o + 3])
    }

    static func hasID3v1(_ url: URL) -> Bool {
        guard let d = try? Data(contentsOf: url), d.count >= 128 else { return false }
        return d[(d.count - 128)..<(d.count - 125)].elementsEqual(Data("TAG".utf8))
    }

    /// (id, corpo) de cada frame, na ordem do arquivo.
    private static func frames(_ url: URL) -> [(id: String, body: Data)] {
        guard let d = try? Data(contentsOf: url), let o = id3Offset(d), d.count > o + 10 else { return [] }
        let version = Int(d[o + 3])
        let end = min(d.count, o + 10 + syncsafe(d, o + 6))
        var p = o + 10
        var out: [(String, Data)] = []
        while p + 10 <= end, d[p] != 0 {
            let id = String(decoding: d[p..<p + 4], as: UTF8.self)
            let size = version == 4 ? syncsafe(d, p + 4) : be32(d, p + 4)
            guard size >= 0, p + 10 + size <= end else { break }
            out.append((id, d[p + 10..<p + 10 + size]))
            p += 10 + size
        }
        return out
    }

    static func id3FrameIDs(_ url: URL) -> [String] { frames(url).map(\.id) }

    static func id3TextFrame(_ url: URL, id: String) -> String? {
        guard let body = frames(url).first(where: { $0.id == id })?.body, let enc = body.first else { return nil }
        let text = body.dropFirst()
        let encoding: String.Encoding = switch enc {
        case 0: .isoLatin1
        case 1: .utf16
        case 2: .utf16BigEndian
        default: .utf8
        }
        return String(data: Data(text), encoding: encoding)?.trimmingCharacters(in: CharacterSet(["\0"]))
    }

    /// Subchunks do LIST/INFO de um WAV (ex.: ["INAM": "Info Title"]).
    static func riffInfo(_ url: URL) -> [String: String] {
        guard let d = try? Data(contentsOf: url), d.starts(with: Data("RIFF".utf8)) else { return [:] }
        var out: [String: String] = [:]
        var p = 12
        while p + 8 <= d.count {
            let id = String(decoding: d[p..<p + 4], as: UTF8.self)
            let size = u32le(d, p + 4)
            if id == "LIST", p + 12 <= d.count, String(decoding: d[p + 8..<p + 12], as: UTF8.self) == "INFO" {
                var q = p + 12
                let end = min(d.count, p + 8 + size)
                while q + 8 <= end {
                    let sid = String(decoding: d[q..<q + 4], as: UTF8.self)
                    let ssize = u32le(d, q + 4)
                    guard q + 8 + ssize <= end else { break }
                    let s = String(decoding: d[q + 8..<q + 8 + ssize], as: UTF8.self)
                    out[sid] = s.trimmingCharacters(in: CharacterSet(["\0"]))
                    q += 8 + ssize + (ssize % 2)
                }
            }
            p += 8 + size + (size % 2)
        }
        return out
    }

    static func snapshotViaSFB(_ url: URL) throws -> TagSnapshot { try TagSnapshot.read(url) }
}
