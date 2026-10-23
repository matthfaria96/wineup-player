import AVFoundation
import Foundation
import SFBAudioEngine

/// Trecho do áudio em PCM mono 44,1 kHz, decodificado pelo SFB (qualquer formato que o app toca).
enum AudioExcerpt {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    /// `seconds` de áudio começando perto de 1/3 da música (evita silêncio e introdução).
    static func read(_ url: URL, seconds: Double = 12) throws -> AVAudioPCMBuffer? {
        let decoder = try AudioDecoder(url: url)
        try decoder.open()
        defer { try? decoder.close() }
        let source = decoder.processingFormat
        let wanted = AVAudioFrameCount(source.sampleRate * seconds)
        if decoder.length > AVAudioFramePosition(wanted) * 2 {
            try decoder.seek(to: min(decoder.length / 3, decoder.length - AVAudioFramePosition(wanted)))
        }
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: wanted) else { return nil }
        try decoder.decode(into: input, length: wanted)
        guard input.frameLength > 0, let converter = AVAudioConverter(from: source, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(44_100 * seconds) + 4096)
        else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return output.frameLength > 0 ? output : nil
    }
}
