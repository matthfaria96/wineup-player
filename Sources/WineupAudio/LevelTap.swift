import AVFoundation
import Accelerate
import Foundation
import os

public struct MeterSnapshot: Sendable {
    public let rms: [Float]
    public let peak: [Float]
    public let samples: [Float]
    public let sampleRate: Double
    public let timestamp: TimeInterval
}

/// Tap único no nó indicado (normalmente o mainMixerNode). Nunca bloqueia a thread de áudio.
public final class LevelTap: @unchecked Sendable {
    static let sampleCount = 1024
    /// Maior bloco considerado no RMS/pico.
    static let maxFrames = 4096

    private struct State {
        var rms: [Float] = [0, 0]
        var peak: [Float] = [0, 0]
        var samples = [Float](repeating: 0, count: LevelTap.sampleCount)
        var sampleRate: Double = 0
        var timestamp: TimeInterval = 0
        var hasData = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private weak var node: AVAudioNode?

    public init() {}

    public func install(on node: AVAudioNode) {
        node.removeTap(onBus: 0)
        self.node = node
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
    }

    public func remove() {
        node?.removeTap(onBus: 0)
        node = nil
    }

    public func snapshot() -> MeterSnapshot? {
        state.withLock { s in
            guard s.hasData else { return nil }
            return MeterSnapshot(rms: s.rms, peak: s.peak, samples: s.samples,
                                 sampleRate: s.sampleRate, timestamp: s.timestamp)
        }
    }

    /// Calcula fora do lock e copia para o estado só se o leitor não estiver ocupado.
    /// Sem buffer compartilhado: callbacks do tap que se sobreponham (reinstalação) não se atropelam.
    func process(buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frames = min(Int(buffer.frameLength), Self.maxFrames)
        guard frames > 0 else { return }
        let channels = Int(buffer.format.channelCount)
        guard channels > 0 else { return }

        var rms: [Float] = [0, 0]
        var peak: [Float] = [0, 0]
        for c in 0..<2 {
            let src = data[min(c, channels - 1)]
            vDSP_rmsqv(src, 1, &rms[c], vDSP_Length(frames))
            vDSP_maxmgv(src, 1, &peak[c], vDSP_Length(frames))
        }
        let count = min(frames, Self.sampleCount)
        // Forma de onda (mono) num buffer local: callbacks sobrepostos não dividem memória.
        var mono = [Float](repeating: 0, count: Self.sampleCount)
        mono.withUnsafeMutableBufferPointer { out in
            guard let base = out.baseAddress else { return }
            if channels >= 2 {
                var half: Float = 0.5
                vDSP_vadd(data[0], 1, data[1], 1, base, 1, vDSP_Length(count))
                vDSP_vsmul(base, 1, &half, base, 1, vDSP_Length(count))
            } else {
                base.update(from: data[0], count: count)
            }
        }
        let (rmsOut, peakOut, samplesOut) = (rms, peak, mono)
        let rate = buffer.format.sampleRate
        let now = ProcessInfo.processInfo.systemUptime
        _ = state.withLockIfAvailable { s in
            s.rms = rmsOut
            s.peak = peakOut
            s.samples = samplesOut
            s.sampleRate = rate
            s.timestamp = now
            s.hasData = true
        }
    }
}
