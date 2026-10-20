import Foundation

/// WAVs de seno contínuo (16 bits) gerados em diretório temporário próprio; removidos no fim.
final class FixtureSet {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wineup-audiocheck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }

    /// `startFrame` desloca a fase para que um segundo arquivo continue exatamente de onde o primeiro parou.
    @discardableResult
    func sine(_ name: String, rate: Int, channels: Int, seconds: Double,
              frequency: Double = 440, startFrame: Int = 0) throws -> URL {
        let frames = Int(Double(rate) * seconds)
        var pcm = Data(capacity: frames * channels * 2)
        for i in 0..<frames {
            let phase = 2 * Double.pi * frequency * Double(i + startFrame) / Double(rate)
            let v = Int16(0.5 * 32_767 * sin(phase))
            for _ in 0..<channels { withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) } }
        }
        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
        var d = Data("RIFF".utf8) + le32(36 + pcm.count) + Data("WAVEfmt ".utf8) + le32(16)
        d += le16(1) + le16(channels) + le32(rate) + le32(rate * channels * 2) + le16(channels * 2) + le16(16)
        d += Data("data".utf8) + le32(pcm.count) + pcm
        let url = dir.appendingPathComponent(name)
        try d.write(to: url)
        return url
    }
}
