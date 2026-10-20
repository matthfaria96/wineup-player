import AVFoundation
import Foundation
import SFBAudioEngine

/// Reprodução real (SFBAudioEngine) com preamp + equalizador de 10 bandas pós-mixer.
final class AudioEngineService: NSObject, AudioPlayer.Delegate {
    static let bandFrequencies: [Float] = [60, 170, 310, 600, 1_000, 2_000, 5_000, 8_000, 12_000, 16_000]

    var onEndOfAudio: (() -> Void)?
    var onError: ((String) -> Void)?

    private let player = AudioPlayer()
    private let equalizer = AVAudioUnitEQ(numberOfBands: AudioEngineService.bandFrequencies.count)

    override init() {
        super.init()
        player.delegate = self
        configureBands()
        insertEqualizer()
    }

    var isPlaying: Bool { player.isPlaying }
    var currentTime: TimeInterval { player.currentTime ?? 0 }
    var totalTime: TimeInterval { player.totalTime ?? 0 }

    func play(_ url: URL) throws { try player.play(url) }
    func pause() { _ = player.pause() }
    func resume() { _ = player.resume() }
    func stop() { player.stop() }

    func seek(toFraction fraction: Double) {
        _ = player.seek(position: min(max(fraction, 0), 1))
    }

    func setVolume(_ volume: Double) {
        try? player.setVolume(Float(min(max(volume, 0), 1)))
    }

    /// Ganhos em dB: `preamp` e uma entrada por banda.
    func applyEqualizer(preamp: Double, bands: [Double], bypass: Bool) {
        equalizer.bypass = bypass
        equalizer.globalGain = Float(preamp)
        for (index, band) in equalizer.bands.enumerated() {
            band.gain = Float(bands.indices.contains(index) ? bands[index] : 0)
        }
    }

    private func configureBands() {
        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = Self.bandFrequencies[index]
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
    }

    /// O SFBAudioEngine só permite mexer entre `sourceNode` e `mainMixerNode`; o EQ entra nesse trecho.
    private func insertEqualizer() {
        player.modifyProcessingGraph { [equalizer, player] engine in
            let format = player.sourceNode.outputFormat(forBus: 0)
            engine.attach(equalizer)
            engine.disconnectNodeOutput(player.sourceNode)
            engine.connect(player.sourceNode, to: equalizer, format: format)
            engine.connect(equalizer, to: player.mainMixerNode, format: format)
        }
    }

    // MARK: AudioPlayer.Delegate (chamado fora da main thread)

    /// Chamado quando o formato muda (ex.: de 44,1 kHz para 96 kHz): refaz a ligação EQ → mixer.
    func audioPlayer(
        _ audioPlayer: AudioPlayer,
        reconfigureProcessingGraph engine: AVAudioEngine,
        with format: AVAudioFormat
    ) -> AVAudioNode {
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        return equalizer
    }

    func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        DispatchQueue.main.async { [weak self] in self?.onEndOfAudio?() }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onError?(error.localizedDescription) }
    }
}
