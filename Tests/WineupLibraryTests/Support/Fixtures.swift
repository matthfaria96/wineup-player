import Foundation
import SFBAudioEngine

enum FixtureError: Error { case processFailed(String), malformed(String) }

/// Geradores de arquivos de 0,5 s, sempre dentro de um diretório de `withTempDir`. Nada é commitado.
enum Fixtures {
    static let png: Data = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    // MARK: WAV

    static func wav(_ dir: URL, name: String = "plain.wav") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try WAVFixture.write(to: url, seconds: 0.5)
        return url
    }

    /// WAV com chunk LIST/INFO (INAM="Info Title", ICRD="2019") depois do `data`.
    static func wavWithInfo(_ dir: URL) throws -> URL {
        let url = try wav(dir, name: "info.wav")
        var d = try Data(contentsOf: url)
        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        func sub(_ id: String, _ text: String) -> Data {
            var body = Data(text.utf8) + Data([0])
            if body.count % 2 == 1 { body.append(0) }
            return Data(id.utf8) + le32(text.utf8.count + 1) + body
        }
        let info = Data("INFO".utf8) + sub("INAM", "Info Title") + sub("ICRD", "2019")
        d += Data("LIST".utf8) + le32(info.count) + info
        d.replaceSubrange(4..<8, with: le32(d.count - 8))
        try d.write(to: url)
        return url
    }

    // MARK: afconvert / SFB

    private static func afconvert(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw FixtureError.processFailed("afconvert \(args): \(msg)")
        }
    }

    private static func viaAfconvert(_ dir: URL, name: String, _ fmt: [String]) throws -> URL {
        let src = try wav(dir, name: "src-\(name).wav")
        let out = dir.appendingPathComponent(name)
        try afconvert(fmt + [src.path, out.path])
        try? FileManager.default.removeItem(at: src)
        return out
    }

    static func flac(_ dir: URL) throws -> URL {
        try viaAfconvert(dir, name: "a.flac", ["-f", "flac", "-d", "flac"])
    }
    static func m4aAAC(_ dir: URL) throws -> URL {
        try viaAfconvert(dir, name: "aac.m4a", ["-f", "m4af", "-d", "aac"])
    }
    static func m4aALAC(_ dir: URL) throws -> URL {
        try viaAfconvert(dir, name: "alac.m4a", ["-f", "m4af", "-d", "alac"])
    }

    private static func viaSFB(_ dir: URL, name: String) throws -> URL {
        let src = try wav(dir, name: "src-\(name).wav")
        let out = dir.appendingPathComponent(name)
        try AudioConverter.convert(src, to: out)
        try? FileManager.default.removeItem(at: src)
        return out
    }
    static func mp3(_ dir: URL) throws -> URL { try viaSFB(dir, name: "a.mp3") }
    static func opus(_ dir: URL) throws -> URL { try viaSFB(dir, name: "a.opus") }
    static func vorbis(_ dir: URL) throws -> URL { try viaSFB(dir, name: "a.ogg") }

    /// Campo personalizado + capas frontCover e backCover (FLAC/Opus/Vorbis/M4A).
    static func withUnknownFields(_ url: URL) throws {
        let file = try AudioFile(readingPropertiesAndMetadataFrom: url)
        file.metadata.additionalMetadata = ["MY_CUSTOM_FIELD": "keepme"]
        file.metadata.attachPicture(AttachedPicture(imageData: png, type: .frontCover))
        file.metadata.attachPicture(AttachedPicture(imageData: png + Data([0]), type: .backCover))
        try file.writeMetadata()
    }

    // MARK: MP3 com ID3 cru

    private static func be32(_ v: Int) -> Data {
        Data([UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)])
    }
    private static func syncsafe(_ v: Int) -> Data {
        Data([UInt8(v >> 21 & 127), UInt8(v >> 14 & 127), UInt8(v >> 7 & 127), UInt8(v & 127)])
    }
    private static func latin1(_ s: String) -> Data { s.data(using: .isoLatin1)! }

    static func rawID3(version: Int) -> Data {
        func frame(_ id: String, _ body: Data) -> Data {
            Data(id.utf8) + (version == 4 ? syncsafe(body.count) : be32(body.count)) + Data([0, 0]) + body
        }
        func text(_ id: String, _ s: String) -> Data { frame(id, Data([0]) + latin1(s)) }
        var tag = Data()
        tag += text("TIT2", "Old")
        tag += text("TPE1", "Artist")
        tag += text(version == 4 ? "TDRC" : "TYER", "2019")
        tag += frame("TXXX", Data([0]) + latin1("MY_CUSTOM") + Data([0]) + latin1("keepme"))
        tag += frame("PRIV", latin1("wineup.test") + Data([0, 1, 2, 3]))
        tag += frame("WXXX", Data([0]) + latin1("site") + Data([0]) + latin1("https://example.com"))
        tag += frame("APIC", Data([0]) + latin1("image/png") + Data([0, 3, 0]) + png)
        tag += frame("APIC", Data([0]) + latin1("image/png") + Data([0, 4, 0]) + png + Data([0]))
        let header = Data("ID3".utf8) + Data([UInt8(version), 0, 0]) + syncsafe(tag.count)
        return header + tag
    }

    static func mp3WithRawID3(_ dir: URL, version: Int) throws -> URL {
        let plain = try mp3(dir)
        let audio = try Data(contentsOf: plain)
        guard !audio.starts(with: Data("ID3".utf8)) else { throw FixtureError.malformed("mp3 já tem ID3") }
        let out = dir.appendingPathComponent("raw\(version).mp3")
        try (rawID3(version: version) + audio).write(to: out)
        try? FileManager.default.removeItem(at: plain)
        return out
    }

    // MARK: M4A com átomo freeform

    /// M4A AAC com capas (via SFB) e um átomo `----` com.test:CUSTOM="keepme" inserido à mão.
    static func m4aWithFreeform(_ dir: URL) throws -> URL {
        let url = try m4aAAC(dir)
        try withUnknownFields(url)
        var d = try Data(contentsOf: url)
        func u32(_ at: Int) -> Int { Int(d[at]) << 24 | Int(d[at + 1]) << 16 | Int(d[at + 2]) << 8 | Int(d[at + 3]) }
        func find(_ type: String, in range: Range<Int>, skip: Int = 0) -> Range<Int>? {
            var p = range.lowerBound + skip
            while p + 8 <= range.upperBound {
                let size = u32(p)
                guard size >= 8, p + size <= range.upperBound else { return nil }
                if String(decoding: d[p + 4..<p + 8], as: UTF8.self) == type { return p..<p + size }
                p += size
            }
            return nil
        }
        guard let moov = find("moov", in: 0..<d.count),
              let udta = find("udta", in: moov.lowerBound + 8..<moov.upperBound),
              let meta = find("meta", in: udta.lowerBound + 8..<udta.upperBound),
              let ilst = find("ilst", in: meta.lowerBound + 8..<meta.upperBound, skip: 4)
        else { throw FixtureError.malformed("estrutura moov/udta/meta/ilst não encontrada") }
        func atom(_ type: String, _ body: Data) -> Data { be32(body.count + 8) + Data(type.utf8) + body }
        let free = atom("----",
            atom("mean", Data([0, 0, 0, 0]) + Data("com.test".utf8)) +
            atom("name", Data([0, 0, 0, 0]) + Data("CUSTOM".utf8)) +
            atom("data", Data([0, 0, 0, 1, 0, 0, 0, 0]) + Data("keepme".utf8)))
        d.insert(contentsOf: free, at: ilst.upperBound)
        for r in [moov, udta, meta, ilst] { d.replaceSubrange(r.lowerBound..<r.lowerBound + 4, with: be32(r.count + free.count)) }
        try d.write(to: url)
        return url
    }
}
