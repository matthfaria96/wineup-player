import AVFoundation
import Foundation
import SFBAudioEngine
import WineupCore
import os

/// Implementa a porta `AudioEngine` sobre o `AudioPlayer` do SFB, com a cadeia de efeitos
/// (velocidade, EQ, balanço/ganho) entre o sourceNode e o mainMixerNode e o medidor no mixer.
public final class SFBAudioEngineAdapter: NSObject, AudioEngine, AudioPlayer.Delegate, @unchecked Sendable {
    private struct State {
        var tokens: [ObjectIdentifier: URL] = [:]
        var rgCache: [URL: ReplayGainInfo] = [:]
        var mode: ReplayGainMode = .off
        var preventClipping = true
    }

    private let player = AudioPlayer()
    private let chain = EffectChain()
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let utility = DispatchQueue(label: "wineup.audio.replaygain", qos: .utility)

    public let meter = LevelTap()

    public var onNowPlayingChanged: ((URL?) -> Void)?
    public var onEndOfAudio: (() -> Void)?
    public var onError: ((String) -> Void)?
    public var onConfigurationChange: ((Double) -> Void)?

    public var replayGainMode: ReplayGainMode {
        get { state.withLock { $0.mode } }
        set { state.withLock { $0.mode = newValue } }
    }

    public var preventClipping: Bool {
        get { state.withLock { $0.preventClipping } }
        set { state.withLock { $0.preventClipping = newValue } }
    }

    public override init() {
        super.init()
        player.delegate = self
        let chain = self.chain
        let source = player.sourceNode
        let mixer = player.mainMixerNode
        // Instalada uma única vez; reconexões posteriores vêm de reconfigureProcessingGraph.
        player.modifyProcessingGraph { engine in
            chain.attach(to: engine)
            engine.disconnectNodeOutput(source)
            chain.connect(engine, from: source, to: mixer, format: source.outputFormat(forBus: 0))
        }
        meter.install(on: mixer)
    }

    // MARK: AudioEngine

    public func play(_ url: URL) throws {
        let decoder = try makeDecoder(url)
        player.clearQueue()
        try player.play(decoder)
    }

    public func enqueue(_ url: URL) throws {
        let decoder = try makeDecoder(url)
        player.clearQueue()
        try player.enqueue(decoder)
    }

    public func pause() { _ = player.pause() }
    public func resume() { _ = player.resume() }
    public func stop() { player.stop() }

    public func seek(toFraction fraction: Double) {
        guard fraction.isFinite else { return }
        _ = player.seek(position: min(max(fraction, 0), 1))
    }

    /// Volume do app no mixer principal. Nunca `player.setVolume` (altera o volume do dispositivo).
    public func setVolume(_ volume: Double) {
        let v = volume.isFinite ? min(max(volume, 0), 1) : 1
        player.mainMixerNode.outputVolume = Float(v)
    }

    public func setRate(_ rate: Double) { chain.setRate(Float(rate)) }
    public func setBalance(_ pan: Double) { chain.setPan(Float(pan)) }
    public func setReplayGain(linear: Double) { chain.setGain(linear: Float(linear)) }

    public func applyEqualizer(preamp: Double, bands: [Double], bypass: Bool) {
        let global = EqMath.effectiveGlobalGain(preamp: preamp, bands: bands)
        chain.applyEqualizer(globalGain: Float(global), bands: bands.map { Float($0) }, bypass: bypass)
    }

    public var currentTime: TimeInterval { player.currentTime ?? 0 }
    public var totalTime: TimeInterval { player.totalTime ?? 0 }
    public var isPlaying: Bool { player.isPlaying }

    /// Apenas para verificação offline (wineup-audiocheck): acesso ao AVAudioEngine do SFB.
    public func withEngine(_ body: (AVAudioEngine) throws -> Void) throws {
        let failure = OSAllocatedUnfairLock<Error?>(initialState: nil)
        withoutActuallyEscaping(body) { escapable in
            player.modifyProcessingGraph { engine in
                do { try escapable(engine) } catch { failure.withLock { $0 = error } }
            }
        }
        if let error = failure.withLock({ $0 }) { throw error }
    }

    // MARK: Decoders / ReplayGain

    private func makeDecoder(_ url: URL) throws -> AudioDecoder {
        let decoder = try AudioDecoder(url: url)
        let id = ObjectIdentifier(decoder)
        state.withLock { $0.tokens[id] = url }
        utility.async { [weak self] in _ = self?.replayGain(for: url) }
        return decoder
    }

    private func replayGain(for url: URL) -> ReplayGainInfo {
        if let cached = state.withLock({ $0.rgCache[url] }) { return cached }
        let info = ReplayGainReader.read(url)
        state.withLock { $0.rgCache[url] = info }
        return info
    }

    // MARK: AudioPlayer.Delegate

    public func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: PCMDecoding?) {
        let url: URL? = nowPlaying.flatMap { decoder in
            let id = ObjectIdentifier(decoder as AnyObject)
            return state.withLock { $0.tokens[id] }
        }
        if let url {
            let (mode, clip) = state.withLock { ($0.mode, $0.preventClipping) }
            let linear = ReplayGainMath.linearGain(mode: mode, info: replayGain(for: url), preventClipping: clip)
            chain.setGain(linear: Float(linear))
        } else {
            // Nada tocando nem na fila: libera os tokens de decoders.
            state.withLock { $0.tokens.removeAll() }
        }
        DispatchQueue.main.async { [weak self] in self?.onNowPlayingChanged?(url) }
    }

    public func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        DispatchQueue.main.async { [weak self] in self?.onEndOfAudio?() }
    }

    public func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        let message = error.localizedDescription
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }

    public func audioPlayer(_ audioPlayer: AudioPlayer, reconfigureProcessingGraph engine: AVAudioEngine,
                            with format: AVAudioFormat) -> AVAudioNode {
        chain.reconnectInternal(engine, to: engine.mainMixerNode, format: format)
        return chain.first
    }

    public func audioPlayer(_ audioPlayer: AudioPlayer, audioEngineConfigurationChange userInfo: [AnyHashable: Any]?) {
        // O SFB já reconecta e reinicia o engine; só reinstalamos o tap e informamos a taxa.
        meter.install(on: audioPlayer.mainMixerNode)
        let rate = audioPlayer.outputNode.outputFormat(forBus: 0).sampleRate
        DispatchQueue.main.async { [weak self] in self?.onConfigurationChange?(rate) }
    }
}
