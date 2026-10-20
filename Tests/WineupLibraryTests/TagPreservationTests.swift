import Foundation
import Testing
@testable import WineupLibrary

enum FormatCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case flac, m4aAAC, m4aALAC, opus, vorbis, mp3v3, mp3v4, wav, wavInfo
    var testDescription: String { rawValue }

    /// Cria a fixture (com campos desconhecidos e capas quando o formato permite).
    func make(_ dir: URL) throws -> URL {
        switch self {
        case .flac: let u = try Fixtures.flac(dir); try Fixtures.withUnknownFields(u); return u
        case .m4aAAC: return try Fixtures.m4aWithFreeform(dir)
        case .m4aALAC: let u = try Fixtures.m4aALAC(dir); try Fixtures.withUnknownFields(u); return u
        case .opus: let u = try Fixtures.opus(dir); try Fixtures.withUnknownFields(u); return u
        case .vorbis: let u = try Fixtures.vorbis(dir); try Fixtures.withUnknownFields(u); return u
        case .mp3v3: return try Fixtures.mp3WithRawID3(dir, version: 3)
        case .mp3v4: return try Fixtures.mp3WithRawID3(dir, version: 4)
        case .wav: return try Fixtures.wav(dir)
        case .wavInfo: return try Fixtures.wavWithInfo(dir)
        }
    }
}

@Suite("SAFE-03: preservação de tags por formato")
struct TagPreservationTests {
    @Test(arguments: FormatCase.allCases)
    func writingTitleChangesOnlyTitle(_ format: FormatCase) async throws {
        try await withTempDir { dir in
            let url = try format.make(dir)
            let before = try TagSnapshot.read(url)
            let backend = try #require(TagBackends.backend(for: url))
            try backend.write(TagChanges(title: "Novo"), to: url)
            let after = try TagSnapshot.read(url)
            #expect(after.fields["title"] == "Novo")
            #expect(after.differences(from: before) == ["title"])
        }
    }

    @Test(arguments: [FormatCase.flac, .opus, .vorbis])
    func xiphKeepsCustomFieldAndPictures(_ format: FormatCase) async throws {
        try await withTempDir { dir in
            let url = try format.make(dir)
            try TagBackends.backend(for: url)!.write(TagChanges(title: "Novo", artist: "Outro"), to: url)
            let after = try TagSnapshot.read(url)
            #expect(after.additional["MY_CUSTOM_FIELD"] == "keepme")
            #expect(after.pictures.map(\.type).sorted() == [3, 4])
            #expect(after.pictures.allSatisfy { $0.byteCount >= Fixtures.png.count })
        }
    }

    @Test func alacKeepsPictures() async throws {
        try await withTempDir { dir in
            let url = try FormatCase.m4aALAC.make(dir)
            try TagBackends.backend(for: url)!.write(TagChanges(title: "Novo"), to: url)
            #expect(try TagSnapshot.read(url).pictures.count == 2)
        }
    }

    private func hasFreeform(_ url: URL) -> Bool {
        guard let d = try? Data(contentsOf: url) else { return false }
        return ["----", "com.test", "CUSTOM", "keepme"].allSatisfy { d.range(of: Data($0.utf8)) != nil }
    }

    @Test func m4aKeepsFreeformAndPictures() async throws {
        try await withTempDir { dir in
            let url = try FormatCase.m4aAAC.make(dir)
            let before = try TagSnapshot.read(url)
            // O SFB não expõe átomos freeform arbitrários em additionalMetadata; a checagem é nos bytes.
            #expect(hasFreeform(url))
            try TagBackends.backend(for: url)!.write(TagChanges(title: "Novo"), to: url)
            let after = try TagSnapshot.read(url)
            #expect(hasFreeform(url))
            // Limitação do formato M4A: o tipo da capa (frente/verso) não existe no 'covr';
            // comparamos só número e bytes.
            #expect(after.pictures.count == before.pictures.count)
            #expect(Set(after.pictures.map(\.sha256)) == Set(before.pictures.map(\.sha256)))
        }
    }

    @Test(arguments: [(FormatCase.mp3v3, 3), (FormatCase.mp3v4, 4)])
    func mp3KeepsVersionAndFrames(_ format: FormatCase, _ version: Int) async throws {
        try await withTempDir { dir in
            let url = try format.make(dir)
            #expect(TagProbe.id3Version(url) == version)
            try TagBackends.backend(for: url)!.write(TagChanges(title: "Novo"), to: url)
            #expect(TagProbe.id3Version(url) == version)
            let ids = TagProbe.id3FrameIDs(url)
            for id in ["TXXX", "PRIV", "WXXX"] { #expect(ids.contains(id), "faltou \(id)") }
            #expect(ids.filter { $0 == "APIC" }.count == 2)
            let yearID = version == 3 ? "TYER" : "TDRC"
            #expect(TagProbe.id3TextFrame(url, id: yearID) == "2019")
            #expect(TagProbe.id3TextFrame(url, id: "TIT2") == "Novo")
            #expect(!TagProbe.hasID3v1(url))
        }
    }

    @Test(arguments: [(FormatCase.mp3v3, "TYER"), (FormatCase.mp3v4, "TDRC")])
    func mp3YearUsesVersionFrame(_ format: FormatCase, _ frame: String) async throws {
        try await withTempDir { dir in
            let url = try format.make(dir)
            try TagBackends.backend(for: url)!.write(TagChanges(year: "2021"), to: url)
            #expect(TagProbe.id3TextFrame(url, id: frame) == "2021")
            let other = frame == "TYER" ? "TDRC" : "TYER"
            #expect(!TagProbe.id3FrameIDs(url).contains(other))
            #expect(!TagProbe.hasID3v1(url))
        }
    }

    @Test func wavYearRoundTrips() async throws {
        try await withTempDir { dir in
            let url = try Fixtures.wav(dir)
            try TagBackends.backend(for: url)!.write(TagChanges(year: "2019"), to: url)
            #expect(try TagSnapshot.read(url).fields["year"] == "2019")
        }
    }

    @Test func wavKeepsInfoChunk() async throws {
        try await withTempDir { dir in
            let url = try Fixtures.wavWithInfo(dir)
            #expect(TagProbe.riffInfo(url)["ICRD"] == "2019")
            try TagBackends.backend(for: url)!.write(TagChanges(title: "Novo"), to: url)
            let info = TagProbe.riffInfo(url)
            #expect(info["ICRD"] == "2019")
            #expect(info["INAM"] == "Info Title")
            #expect(TagProbe.id3Version(url) != nil)
        }
    }

    @Test func unsupportedExtensionHasNoBackend() {
        #expect(TagBackends.backend(for: URL(fileURLWithPath: "/x/a.xyz")) == nil)
    }
}
