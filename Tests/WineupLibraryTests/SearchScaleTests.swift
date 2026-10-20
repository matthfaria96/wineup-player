import Foundation
import Testing
@testable import WineupLibrary

struct SearchScaleTests {
    private func median(_ body: () async throws -> Void) async throws -> Duration {
        try await body()  // aquecimento
        var times: [Duration] = []
        for _ in 0..<5 {
            let t = try await ContinuousClock().measure { try await body() }
            times.append(t)
        }
        return times.sorted()[2]
    }

    @Test(.timeLimit(.minutes(2))) func hundredThousandTracks() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            let gen = try await ContinuousClock().measure {
                try await SyntheticLibrary.insert(count: 100_000, into: db, rootPath: "/synthetic")
            }
            #expect(gen < .seconds(60))
            let search = SearchService(database: db)
            let browse = BrowseService(database: db)

            // Atraso da main enquanto as buscas rodam em segundo plano.
            let worker = Task.detached {
                for _ in 0..<3 {
                    _ = try await search.search("beyonce"); _ = try await search.search("art")
                    _ = try await browse.artists()
                }
            }
            var maxDelay = Duration.zero
            for _ in 0..<20 {
                let t = try await ContinuousClock().measure {
                    try await Task.sleep(for: .milliseconds(20))
                }
                maxDelay = max(maxDelay, t - .milliseconds(20))
            }
            try await worker.value
            #expect(maxDelay < .milliseconds(150))

            for q in ["beyonce", "art", "album 42"] {
                let m = try await median { _ = try await search.search(q) }
                #expect(m < .milliseconds(100), "busca \(q): \(m)")
            }
            #expect(try await search.search("beyonce").count == 200)
            let a = try await median { _ = try await browse.artists() }
            #expect(a < .milliseconds(200), "artists: \(a)")
            let p = try await median { _ = try await browse.allTracks(limit: 200, offset: 50_000) }
            #expect(p < .milliseconds(200), "allTracks: \(p)")
        }
    }
}
