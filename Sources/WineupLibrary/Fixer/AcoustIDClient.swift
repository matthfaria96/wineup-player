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

    /// Roda o fpcalc sem prender uma thread do pool de tarefas esperando o processo terminar:
    /// a saída é lida numa fila do GCD e o fim chega pelo `terminationHandler`.
    public static func fingerprint(_ url: URL, fpcalc: String) async throws -> Fingerprint? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: fpcalc)
        p.arguments = ["-json", url.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let result = ProcessResult()
        let done = DispatchGroup()
        let (data, status): (Data, Int32) = try await withCheckedThrowingContinuation { continuation in
            done.enter()
            p.terminationHandler = { process in result.setStatus(process.terminationStatus); done.leave() }
            do { try p.run() } catch {
                p.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            done.enter()
            // Lê até o fim enquanto o processo escreve (o cano tem limite: sem isto o fpcalc pode travar).
            DispatchQueue.global(qos: .utility).async {
                result.setData(out.fileHandleForReading.readDataToEndOfFile())
                done.leave()
            }
            done.notify(queue: .global(qos: .utility)) { continuation.resume(returning: result.value) }
        }
        return try parseFingerprint(data, status: status)
    }

    static func parseFingerprint(_ data: Data, status: Int32) throws -> Fingerprint? {
        guard status == 0,
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

/// Saída e código de término do fpcalc (preenchidos em filas diferentes).
private final class ProcessResult: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var status: Int32 = -1

    func setData(_ d: Data) { lock.withLock { data = d } }
    func setStatus(_ s: Int32) { lock.withLock { status = s } }
    var value: (Data, Int32) { lock.withLock { (data, status) } }
}
