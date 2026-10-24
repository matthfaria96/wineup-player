import AVFoundation
import Accelerate
import Foundation
import os

public struct MeterSnapshot: Sendable {
    public let rms: [Float]
    public let timestamp: TimeInterval
}

/// Tap único no nó indicado (normalmente o mainMixerNode). Nunca bloqueia a thread de áudio.
public final class LevelTap: @unchecked Sendable {
    /// Maior bloco considerado no RMS.
    static let maxFrames = 4096

    private struct State {
        var rms: [Float] = [0, 0]
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
            return MeterSnapshot(rms: s.rms, timestamp: s.timestamp)
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
        for c in 0..<2 {
            vDSP_rmsqv(data[min(c, channels - 1)], 1, &rms[c], vDSP_Length(frames))
        }
        let rmsOut = rms
        let now = ProcessInfo.processInfo.systemUptime
        _ = state.withLockIfAvailable { s in
            s.rms = rmsOut
            s.timestamp = now
            s.hasData = true
        }
    }
}
