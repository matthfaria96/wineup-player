import Accelerate
import Foundation

/// Analisador de espectro (FFT + bandas log). Uso apenas fora da thread de áudio (lado UI).
public final class SpectrumAnalyzer: @unchecked Sendable {
    public let size: Int
    public let bandCount: Int
    private let minHz: Double
    private let maxHz: Double
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]

    public init(size: Int = 1024, bandCount: Int = 20, minHz: Double = 40, maxHz: Double = 16_000) {
        let n = max(64, size)
        // potência de 2 imediatamente >= n
        let l2 = vDSP_Length(ceil(log2(Double(n))))
        self.size = 1 << Int(l2)
        self.log2n = l2
        self.bandCount = max(1, bandCount)
        self.minHz = minHz
        self.maxHz = maxHz
        self.setup = vDSP_create_fftsetup(l2, FFTRadix(kFFTRadix2))!
        var w = [Float](repeating: 0, count: self.size)
        vDSP_hann_window(&w, vDSP_Length(self.size), Int32(vDSP_HANN_NORM))
        self.window = w
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Bandas normalizadas 0...1 (piso -60 dB). Entradas de tamanho diferente são truncadas/preenchidas com zero.
    public func bands(samples: [Float], sampleRate: Double) -> [Float] {
        let n = size
        let half = n / 2
        var input = [Float](repeating: 0, count: n)
        let take = min(n, samples.count)
        for i in 0..<take { input[i] = samples[i].isFinite ? samples[i] : 0 }
        vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(n))

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                input.withUnsafeBufferPointer { inp in
                    inp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }
        // zrip devolve o dobro; normaliza por n (amplitude de seno unitário ~ 0,5 com Hann normalizada).
        var scale = Float(1.0) / Float(n)
        vDSP_vsmul(mags, 1, &scale, &mags, 1, vDSP_Length(half))

        let binHz = max(1, sampleRate) / Double(n)
        let nyquist = sampleRate / 2
        let top = min(maxHz, nyquist)
        var result = [Float](repeating: 0, count: bandCount)
        let ratio = log(top / minHz)
        guard top > minHz, ratio.isFinite else { return result }
        for b in 0..<bandCount {
            let lo = minHz * exp(ratio * Double(b) / Double(bandCount))
            let hi = minHz * exp(ratio * Double(b + 1) / Double(bandCount))
            var i0 = Int((lo / binHz).rounded(.down))
            var i1 = Int((hi / binHz).rounded(.up))
            i0 = min(max(1, i0), half - 1)
            i1 = min(max(i0 + 1, i1), half)
            var peak: Float = 0
            for i in i0..<i1 { peak = max(peak, mags[i]) }
            let db = 20 * log10(max(peak, 1e-9))
            result[b] = MeterMath.dbToMeter(db)
        }
        return result
    }
}

public enum MeterMath {
    public static let floorDB: Float = -60

    public static func dbToMeter(_ db: Float) -> Float {
        guard db.isFinite else { return db > 0 ? 1 : 0 }
        return min(1, max(0, (db - floorDB) / -floorDB))
    }

    /// Pico de amostra (amplitude 0...1) na escala do medidor. É o pico, não a média (RMS), que chega ao fim
    /// da escala: música masterizada tem média por volta de −9 a −14 dBFS, mas os picos encostam em 0 dBFS.
    public static func peakToMeter(_ amplitude: Float) -> Float {
        dbToMeter(20 * log10(max(abs(amplitude), 1e-9)))
    }

    public static func isStale(timestamp: TimeInterval, now: TimeInterval, maxAge: TimeInterval = 0.1) -> Bool {
        now - timestamp > maxAge
    }

    /// Sobe imediato, desce linear (`decayPerSecond` unidades normalizadas por segundo).
    public static func ballistic(current: Float, target: Float, dt: Float, decayPerSecond: Float = 1.5) -> Float {
        if target >= current { return target }
        return max(target, current - decayPerSecond * max(0, dt))
    }
}
