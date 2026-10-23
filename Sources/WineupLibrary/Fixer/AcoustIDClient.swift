import Foundation

/// Identificação por impressão digital acústica: `fpcalc` (Chromaprint) + API do AcoustID.
/// Opcional: só funciona com o fpcalc instalado e uma chave de aplicativo do AcoustID.
public struct AcoustIDClient: Sendable {
    public struct Fingerprint: Sendable, Equatable {
        public let duration: Int
        public let value: String
    }

    private let fetcher: HTTPFetching
    private let apiKey: String
    private let pacer = RequestPacer(interval: 0.34)

    public init(apiKey: String, fetcher: HTTPFetching = URLSessionFetcher()) {
        self.apiKey = apiKey
        self.fetcher = fetcher
    }

    /// Onde o fpcalc costuma estar (Homebrew, MacPorts, PATH).
    public static func fpcalcPath() -> String? {
        let env = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"] + env
        return dirs.map { "\($0)/fpcalc" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func fingerprint(_ url: URL, fpcalc: String) throws -> Fingerprint? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: fpcalc)
        p.arguments = ["-json", url.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fp = o["fingerprint"] as? String else { return nil }
        let d = (o["duration"] as? Double) ?? (o["duration"] as? Int).map(Double.init) ?? 0
        return Fingerprint(duration: Int(d.rounded()), value: fp)
    }

    /// MBIDs de gravação com a pontuação do AcoustID (0...1), melhor primeiro.
    public func lookup(_ fp: Fingerprint) async throws -> [(recordingID: String, score: Double)] {
        guard let url = FixerHTTP.url("https://api.acoustid.org/v2/lookup",
                                      [("client", apiKey), ("meta", "recordingids"),
                                       ("duration", String(fp.duration)), ("fingerprint", fp.value)])
        else { return [] }
        await pacer.wait()
        let json = try await FixerHTTP.json(fetcher, url) as? [String: Any]
        return Self.parse(json ?? [:])
    }

    static func parse(_ json: [String: Any]) -> [(recordingID: String, score: Double)] {
        guard json["status"] as? String == "ok" else { return [] }
        var out: [(String, Double)] = []
        for r in json["results"] as? [[String: Any]] ?? [] {
            let score = r["score"] as? Double ?? 0
            for rec in r["recordings"] as? [[String: Any]] ?? [] {
                if let id = rec["id"] as? String, !out.contains(where: { $0.0 == id }) { out.append((id, score)) }
            }
        }
        return out.sorted { $0.1 > $1.1 }.map { (recordingID: $0.0, score: $0.1) }
    }
}
