import Foundation

public enum FixerNetworkError: Error, Equatable {
    case notFound
    case rateLimited
    case badStatus(Int)
    case badResponse
}

/// Busca HTTP trocável nos testes.
public protocol HTTPFetching: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
}

public struct URLSessionFetcher: HTTPFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FixerNetworkError.badResponse }
        return (data, http.statusCode)
    }
}

/// Garante um intervalo mínimo entre pedidos ao mesmo serviço (MusicBrainz pede 1 por segundo).
actor RequestPacer {
    private let interval: TimeInterval
    private var next = Date.distantPast

    init(interval: TimeInterval) { self.interval = interval }

    func wait() async {
        let now = Date()
        let start = max(now, next)
        next = start.addingTimeInterval(interval)
        let delay = start.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }
}

enum FixerHTTP {
    static let userAgent = "WineupPlayer/1.0 ( https://witchmymac.com )"

    /// GET de JSON; serviço ocupado (429/503) tenta de novo até duas vezes, com espera crescente.
    static func json(_ fetcher: HTTPFetching, _ url: URL, headers: [String: String] = [:],
                     retryDelay: TimeInterval = 1.5) async throws -> Any {
        var attempt = 0
        while true {
            do {
                return try await jsonOnce(fetcher, url, headers: headers)
            } catch FixerNetworkError.rateLimited where attempt < 2 {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(retryDelay * Double(attempt) * 1_000_000_000))
            }
        }
    }

    private static func jsonOnce(_ fetcher: HTTPFetching, _ url: URL, headers: [String: String]) async throws -> Any {
        let (data, status) = try await fetcher.get(url, headers: ["User-Agent": userAgent, "Accept": "application/json"]
            .merging(headers) { $1 })
        switch status {
        case 200..<300: break
        case 404: throw FixerNetworkError.notFound
        case 429, 503: throw FixerNetworkError.rateLimited
        default: throw FixerNetworkError.badStatus(status)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func url(_ base: String, _ query: [(String, String)]) -> URL? {
        var c = URLComponents(string: base)
        c?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return c?.url
    }
}
