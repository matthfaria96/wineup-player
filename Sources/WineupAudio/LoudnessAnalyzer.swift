import AVFoundation
import Foundation
import SFBAudioEngine
import WineupCore
import os

/// Mede o volume de um arquivo (decodifica tudo pelo SFB) e guarda o resultado em disco,
/// para cada música ser medida uma vez só. Nunca grava no arquivo de áudio.
public final class LoudnessAnalyzer: @unchecked Sendable {
    public static let shared = LoudnessAnalyzer()

    private struct Entry: Codable { var size: Int64; var modified: Double; var info: LoudnessInfo }

    private let storeURL: URL
    private let cache = OSAllocatedUnfairLock(initialState: [String: Entry]())
    private let saveQueue = DispatchQueue(label: "wineup.loudness.save", qos: .utility)

    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Wineup", isDirectory: true)) {
        storeURL = directory.appendingPathComponent("loudness.json")
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache.withLock { $0 = saved }
        }
    }

    /// Medida já guardada (e o arquivo não mudou desde então).
    public func cached(_ url: URL) -> LoudnessInfo? {
        guard let stamp = Self.stamp(url) else { return nil }
        return cache.withLock { c in
            guard let e = c[url.path], e.size == stamp.size, e.modified == stamp.modified else { return nil }
            return e.info
        }
    }

    /// Mede (ou devolve do cache). Lento para arquivos grandes: chame fora da thread principal.
    public func measure(_ url: URL) -> LoudnessInfo? {
        if let hit = cached(url) { return hit }
        guard let stamp = Self.stamp(url), let info = Self.analyze(url) else { return nil }
        cache.withLock { $0[url.path] = Entry(size: stamp.size, modified: stamp.modified, info: info) }
        persist()
        return info
    }

    public var measuredCount: Int { cache.withLock { $0.count } }

    private func persist() {
        let snapshot = cache.withLock { $0 }
        let url = storeURL
        saveQueue.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
    }

    private static func stamp(_ url: URL) -> (size: Int64, modified: Double)? {
        guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = v.fileSize, let date = v.contentModificationDate else { return nil }
        return (Int64(size), date.timeIntervalSince1970)
    }

    /// Decodifica em blocos, converte para Float32 não intercalado e passa pelo medidor BS.1770.
    static func analyze(_ url: URL) -> LoudnessInfo? {
        guard let decoder = try? AudioDecoder(url: url), (try? decoder.open()) != nil else { return nil }
        defer { try? decoder.close() }
        let source = decoder.processingFormat
        guard let target = AVAudioFormat(standardFormatWithSampleRate: source.sampleRate,
                                         channels: min(source.channelCount, 2)) else { return nil }
        let converter = source == target ? nil : AVAudioConverter(from: source, to: target)
        let chunk: AVAudioFrameCount = 65_536
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: chunk),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: chunk) else { return nil }
        var meter = LoudnessMeter(sampleRate: target.sampleRate, channels: Int(target.channelCount))
        while true {
            guard (try? decoder.decode(into: input, length: chunk)) != nil, input.frameLength > 0 else { break }
            let buffer: AVAudioPCMBuffer
            if let converter {
                var fed = false
                output.frameLength = 0
                converter.convert(to: output, error: nil) { _, status in
                    if fed { status.pointee = .noDataNow; return nil }
                    fed = true
                    status.pointee = .haveData
                    return input
                }
                buffer = output
            } else {
                buffer = input
            }
            guard let data = buffer.floatChannelData else { break }
            let frames = Int(buffer.frameLength)
            let planar = (0..<Int(buffer.format.channelCount)).map { UnsafeBufferPointer(start: data[$0], count: frames) }
            meter.process(planar)
        }
        guard let lufs = meter.integrated() else { return nil }
        return LoudnessInfo(integrated: lufs, peak: meter.peak)
    }
}
