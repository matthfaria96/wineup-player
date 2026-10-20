import AVFoundation
import Accelerate
import Foundation
@testable import WineupAudio

enum TestSignal {
    case sine(freq: Double, amplitude: Float, channels: Int)
    case whiteNoise(amplitude: Float)
    case leftOnlySine(freq: Double, amplitude: Float)
}

enum OfflineRender {
    static let sampleRate = 44_100.0

    /// Monta engine comum + fonte -> chain -> mainMixer e renderiza offline.
    /// `configure` roda antes de iniciar; `prepare` permite instalar taps. Devolve amostras por canal (estéreo).
    static func render(
        _ signal: TestSignal,
        seconds: Double = 1.0,
        discard: Int = 8192,
        configure: (EffectChain) -> Void = { _ in },
        engineHook: (AVAudioEngine) -> Void = { _ in }
    ) throws -> [[Float]] {
        let engine = AVAudioEngine()
        let chain = EffectChain()
        let channels: Int
        switch signal {
        case .sine(_, _, let c): channels = c
        default: channels = 2
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))!
        var phase = 0.0
        var seed: UInt64 = 0x9E3779B97F4A7C15
        let source = AVAudioSourceNode(format: format) { _, _, frames, abl in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            for i in 0..<Int(frames) {
                var sample: Float
                var right: Float
                switch signal {
                case .sine(let f, let a, _):
                    sample = a * Float(sin(phase)); right = sample
                    phase += 2 * .pi * f / OfflineRender.sampleRate
                case .leftOnlySine(let f, let a):
                    sample = a * Float(sin(phase)); right = 0
                    phase += 2 * .pi * f / OfflineRender.sampleRate
                case .whiteNoise(let a):
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    sample = a * (Float(seed >> 40) / Float(1 << 24) * 2 - 1)
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    right = a * (Float(seed >> 40) / Float(1 << 24) * 2 - 1)
                }
                for (c, b) in list.enumerated() {
                    b.mData!.assumingMemoryBound(to: Float.self)[i] = c == 0 ? sample : right
                }
            }
            return noErr
        }
        engine.attach(source)
        chain.attach(to: engine)
        chain.connect(engine, from: source, to: engine.mainMixerNode, format: format)
        configure(chain)

        let renderFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)
        engineHook(engine)
        try engine.start()
        defer { engine.stop() }

        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        var out: [[Float]] = [[], []]
        let total = Int(seconds * sampleRate) + discard
        var rendered = 0
        while rendered < total {
            let status = try engine.renderOffline(4096, to: buffer)
            guard status == .success else { break }
            let n = Int(buffer.frameLength)
            for c in 0..<2 {
                out[c].append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![c], count: n))
            }
            rendered += n
        }
        return out.map { Array($0.dropFirst(discard)) }
    }

    static func rmsDB(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return -120 }
        var r: Float = 0
        vDSP_rmsqv(x, 1, &r, vDSP_Length(x.count))
        return r <= 1e-6 ? -120 : max(-120, 20 * log10(r))
    }

    /// Energia (dB) entre `low` e `high` Hz usando FFT com janela Hann (blocos de 8192, média).
    static func bandEnergyDB(samples: [Float], low: Double, high: Double, sampleRate: Double) -> Float {
        let n = 8192
        let log2n = vDSP_Length(13)
        guard samples.count >= n, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return -120 }
        defer { vDSP_destroy_fftsetup(setup) }
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var power = [Float](repeating: 0, count: n / 2)
        var blocks = 0
        var start = 0
        while start + n <= samples.count {
            var block = [Float](repeating: 0, count: n)
            vDSP_vmul(Array(samples[start..<start + n]), 1, window, 1, &block, 1, vDSP_Length(n))
            var re = [Float](repeating: 0, count: n / 2)
            var im = [Float](repeating: 0, count: n / 2)
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    block.withUnsafeBufferPointer { bp in
                        bp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    for k in 0..<(n / 2) { power[k] += split.realp[k] * split.realp[k] + split.imagp[k] * split.imagp[k] }
                }
            }
            blocks += 1
            start += n
        }
        let binHz = sampleRate / Double(n)
        let lo = max(1, Int(low / binHz)), hi = min(n / 2 - 1, Int(high / binHz))
        guard hi >= lo, blocks > 0 else { return -120 }
        var sum: Float = 0
        for k in lo...hi { sum += power[k] }
        return sum <= 0 ? -120 : 10 * log10(sum / Float(blocks))
    }
}
