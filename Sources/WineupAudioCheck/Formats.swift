import AVFoundation
import Foundation
import SFBAudioEngine

/// Codifica um seno em cada formato e decodifica com o mesmo decodificador do player:
/// confere que sai som (RMS) e que a duração bate.
func checkFormats(_ fx: FixtureSet) throws -> [String] {
    let wav = try fx.sine("formats.wav", rate: 44_100, channels: 2, seconds: 2)
    var results: [String] = []
    var failures: [String] = []

    // afconvert (Apple) para os formatos que ele escreve; SFB para os demais.
    let viaApple: [(String, [String])] = [
        ("flac", ["-f", "flac", "-d", "flac"]), ("m4a", ["-f", "m4af", "-d", "aac"]),
        ("alac.m4a", ["-f", "m4af", "-d", "alac"]), ("aiff", ["-f", "AIFF", "-d", "BEI16"]),
        ("caf", ["-f", "caff", "-d", "LEI16"]),
    ]
    // APE fica de fora: o codificador Monkey's Audio da SFB 0.14 cai ao gerar o arquivo de teste
    // (a leitura de .ape continua suportada pelo player).
    let viaSFB = ["mp3", "ogg", "opus", "wv", "tta", "spx"]
    var files: [(String, URL)] = [("wav", wav)]
    for (ext, args) in viaApple {
        let out = fx.dir.appendingPathComponent("formats.\(ext)")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        p.arguments = args + [wav.path, out.path]
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0 { files.append((ext, out)) } else { failures.append("\(ext): afconvert falhou") }
    }
    for ext in viaSFB {
        let out = fx.dir.appendingPathComponent("formats.\(ext)")
                do {
            try AudioConverter.convert(wav, to: out)
            files.append((ext, out))
        } catch {
            failures.append("\(ext): codificação falhou (\(error.localizedDescription))")
        }
    }

    for (ext, url) in files {
                do {
            let decoder = try AudioDecoder(url: url)
            try decoder.open()
            let format = decoder.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { continue }
            var frames: AVAudioFramePosition = 0
            var sum = 0.0, count = 0
            repeat {
                try decoder.decode(into: buffer, length: 8192)
                frames += AVAudioFramePosition(buffer.frameLength)
                for i in stride(from: 0, to: Int(buffer.frameLength), by: 16) {
                    let v = sample(buffer, i)
                    sum += v * v
                    count += 1
                }
            } while buffer.frameLength > 0
            let seconds = Double(frames) / format.sampleRate
            let rmsDB = 10 * log10(max(sum / Double(max(count, 1)), 1e-12))
            if abs(seconds - 2) < 0.15, rmsDB > -20 {
                results.append(ext)
            } else {
                failures.append(String(format: "%@: %.2fs, %.0f dB", ext, seconds, rmsDB))
            }
        } catch {
            failures.append("\(ext): decodificação falhou (\(error.localizedDescription))")
        }
    }
    if !failures.isEmpty { throw CheckError("ok: \(results.joined(separator: ", ")) | falhas: \(failures.joined(separator: "; "))") }
    return results
}

/// Amostra normalizada (-1...1) do canal 0, em qualquer formato de PCM do decodificador.
private func sample(_ buffer: AVAudioPCMBuffer, _ i: Int) -> Double {
    let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
    if let f = buffer.floatChannelData { return Double(f[0][i * stride]) }
    if let s = buffer.int16ChannelData { return Double(s[0][i * stride]) / 32_768 }
    if let s = buffer.int32ChannelData { return Double(s[0][i * stride]) / 2_147_483_648 }
    return 0
}
