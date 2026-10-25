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
        var eq: (preamp: Double, bands: [Double], bypass: Bool) = (0, [], false)
        /// Correção de Som: todas as faixas no mesmo volume percebido (alvo em LUFS).
        var correction = false
        var target = SoundCorrection.defaultTarget
        var current: URL?
        /// Última faixa pedida em play() e a pré-enfileirada (gapless).
        var requested: URL?
        var next: URL?
        /// Decoder entregue a play(): a troca para ele não é um avanço gapless.
        var startToken: ObjectIdentifier?
        /// Conta os play(): avisos de fim/falha atrasados de uma reprodução anterior são descartados.
        var generation = 0
        /// Medição de volume: só a atual e a próxima, sem repetir a que já está sendo medida.
        var pendingMeasure: [URL] = []
        var measuring: URL?
        var measureWorker = false

        /// Ainda vale medir: Correção de Som ligada e a faixa é a atual, a pedida ou a próxima.
        func wantsMeasure(_ url: URL) -> Bool {
            correction && (url == current || url == requested || url == next)
        }
    }

    /// Onde começar a tocar: segundos do arquivo ou fração (0...1).
    public enum StartPoint: Sendable, Equatable {
        case time(Double)
        case fraction(Double)
    }

    private let player = AudioPlayer()
    private let chain = EffectChain()
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let utility = DispatchQueue(label: "wineup.audio.replaygain", qos: .utility)
    private let analysis = DispatchQueue(label: "wineup.audio.loudness", qos: .utility)

    public let meter = LevelTap()

    public var onNowPlayingChanged: ((URL?) -> Void)?
    /// Como onNowPlayingChanged, dizendo se a troca veio da fila (gapless) ou de play().
    public var onTrackChanged: ((URL?, _ fromQueue: Bool) -> Void)?
    /// Arquivo que não abriu ou falhou no meio da decodificação. `ended`: nada mais tocando nem na fila.
    /// Sem ele, a falha vai para onError.
    public var onDecodingFailed: ((URL?, _ message: String, _ ended: Bool) -> Void)?
    public var onEndOfAudio: (() -> Void)?
    public var onError: ((String) -> Void)?
    public var onConfigurationChange: ((Double) -> Void)?

    public var replayGainMode: ReplayGainMode {
        get { state.withLock { $0.mode } }
        set { state.withLock { $0.mode = newValue }; refreshGain() }
    }

    public var soundCorrection: Bool {
        get { state.withLock { $0.correction } }
        set {
            state.withLock { $0.correction = newValue }
            refreshGain()
            guard newValue else { return }
            // Ligou: mede a atual primeiro, depois a próxima.
            let (current, next) = state.withLock { ($0.current ?? $0.requested, $0.next) }
            if let current { requestMeasure(current, urgent: true) }
            if let next { requestMeasure(next, urgent: false) }
        }
    }

    public var correctionTarget: Double {
        get { state.withLock { $0.target } }
        set { state.withLock { $0.target = newValue }; refreshGain() }
    }

    public var preventClipping: Bool {
        get { state.withLock { $0.preventClipping } }
        set {
            state.withLock { $0.preventClipping = newValue }
            chain.setLimiter(on: newValue)
            refreshEqualizer()
        }
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
        chain.setLimiter(on: true)
        if Self.silent { mixer.outputVolume = 0 }
        // Medidor no fim da cadeia (com EQ e Correção de Som), antes do volume do app: as barras mostram a
        // música, e não somem quando o volume do Wineup está baixo.
        meter.install(on: chain.limiter)
        // Carrega as medidas guardadas fora da thread principal.
        analysis.async { LoudnessAnalyzer.shared.prewarm() }
    }

    // MARK: AudioEngine

    public func play(_ url: URL) throws { try play(url, from: nil) }

    /// Toca já a partir de `start`: o decoder é aberto e posicionado antes de entrar no player
    /// (um seek logo depois de play() era descartado, porque o decoder ainda não estava ativo).
    public func play(_ url: URL, from start: StartPoint?) throws {
        let decoder = try makeDecoder(url, start: start)
        let token = ObjectIdentifier(decoder)
        state.withLock {
            $0.requested = url
            $0.next = nil
            $0.startToken = token
            $0.generation += 1
        }
        requestMeasure(url, urgent: true)
        player.clearQueue()
        try player.play(decoder)
    }

    public func enqueue(_ url: URL) throws {
        let decoder = try makeDecoder(url, start: nil)
        state.withLock { $0.next = url }
        requestMeasure(url, urgent: false)
        player.clearQueue()
        try player.enqueue(decoder)
    }

    /// Esvazia a próxima faixa pré-enfileirada.
    public func clearQueue() {
        state.withLock { $0.next = nil }
        player.clearQueue()
    }

    public func pause() { _ = player.pause() }
    public func resume() { _ = player.resume() }
    public func stop() { player.stop() }

    /// Pula para um instante absoluto do arquivo (segundos).
    public func seek(toTime time: Double) {
        guard time.isFinite, time >= 0 else { return }
        _ = player.seek(time: time)
    }

    public func seek(toFraction fraction: Double) {
        guard fraction.isFinite else { return }
        _ = player.seek(position: min(max(fraction, 0), 1))
    }

    /// Volume do app no mixer principal. Nunca `player.setVolume` (altera o volume do dispositivo).
    public func setVolume(_ volume: Double) {
        let v = volume.isFinite ? min(max(volume, 0), 1) : 1
        player.mainMixerNode.outputVolume = Self.silent ? 0 : Float(v)
    }

    /// Capturas de tela (WINEUP_SILENT=1): toca sem sair som, com o volume da tela intacto.
    private static let silent = ProcessInfo.processInfo.environment["WINEUP_SILENT"] != nil

    public func setRate(_ rate: Double) { chain.setRate(Float(rate)) }
    public func setBalance(_ pan: Double) { chain.setPan(Float(pan)) }

    /// L (-1), normal (0) ou R (1): em L/R a música inteira fica num lado só.
    public func setSide(_ side: Int) {
        let chain = chain
        // Sob o mutex do engine do SFB; religa só downmix -> balanço.
        try? withEngine { engine in
            var format = chain.downmix.inputFormat(forBus: 0)
            if format.channelCount == 0 || format.sampleRate == 0 {
                format = engine.mainMixerNode.outputFormat(forBus: 0)
            }
            chain.setSide(side, engine: engine, format: format)
        }
    }

    public func applyEqualizer(preamp: Double, bands: [Double], bypass: Bool) {
        state.withLock { $0.eq = (preamp, bands, bypass) }
        refreshEqualizer()
    }

    /// Com o limitador ligado, o EQ só abaixa metade do pico das bandas: o resto o limitador segura sem
    /// distorcer. Abaixar o pico inteiro deixava a música toda mais baixa e "pior" a cada reforço.
    private func refreshEqualizer() {
        let (eq, limited) = state.withLock { ($0.eq, $0.preventClipping) }
        let global = EqMath.effectiveGlobalGain(preamp: eq.preamp, bands: eq.bands, share: limited ? 0.5 : 1)
        chain.applyEqualizer(globalGain: Float(global), bands: eq.bands.map { Float($0) }, bypass: eq.bypass)
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

    private func makeDecoder(_ url: URL, start: StartPoint?) throws -> AudioDecoder {
        let decoder = try AudioDecoder(url: url)
        if let start { try position(decoder, at: start) }
        let id = ObjectIdentifier(decoder)
        state.withLock { $0.tokens[id] = url }
        utility.async { [weak self] in _ = self?.replayGain(for: url) }
        return decoder
    }

    /// Abre o decoder e o leva ao ponto inicial. Se o formato não permitir seek, começa do início.
    private func position(_ decoder: AudioDecoder, at start: StartPoint) throws {
        try decoder.open()
        guard decoder.supportsSeeking else { return }
        let length = decoder.length
        let frame: AVAudioFramePosition
        switch start {
        case .time(let seconds):
            guard seconds.isFinite, seconds > 0 else { return }
            frame = AVAudioFramePosition(seconds * decoder.processingFormat.sampleRate)
        case .fraction(let fraction):
            guard fraction.isFinite, fraction > 0, length > 0 else { return }
            frame = AVAudioFramePosition(Double(length) * min(fraction, 1))
        }
        let target = length > 0 ? min(frame, length - 1) : frame
        guard target > 0 else { return }
        try? decoder.seek(to: target)
    }

    private func replayGain(for url: URL) -> ReplayGainInfo {
        if let cached = state.withLock({ $0.rgCache[url] }) { return cached }
        let info = ReplayGainReader.read(url)
        state.withLock { $0.rgCache[url] = info }
        return info
    }

    // MARK: Correção de Som

    /// Pede a medição de volume (só com a Correção de Som ligada). `urgent` passa na frente (faixa que vai tocar).
    /// Faixas que já não são a atual nem a próxima saem da fila; a que está sendo medida não entra de novo.
    private func requestMeasure(_ url: URL, urgent: Bool) {
        let start = state.withLock { s -> Bool in
            guard s.wantsMeasure(url), s.measuring != url else { return false }
            var pending = s.pendingMeasure.filter { $0 != url && s.wantsMeasure($0) }
            if urgent { pending.insert(url, at: 0) } else { pending.append(url) }
            s.pendingMeasure = pending
            guard !s.measureWorker else { return false }
            s.measureWorker = true
            return true
        }
        if start { analysis.async { [weak self] in self?.measureLoop() } }
    }

    /// Mede uma faixa por vez até a fila esvaziar. Cancela a leitura se a faixa sair de cena.
    private func measureLoop() {
        while let url = nextToMeasure() {
            let info = LoudnessAnalyzer.shared.measure(url) { [weak self] in
                !(self?.state.withLock { $0.wantsMeasure(url) } ?? false)
            }
            state.withLock { $0.measuring = nil }
            // Medida pronta: se for a faixa tocando, aplica o ganho.
            if info != nil, state.withLock({ $0.current == url && $0.correction }) { refreshGain() }
        }
    }

    private func nextToMeasure() -> URL? {
        state.withLock { s in
            s.pendingMeasure = s.pendingMeasure.filter { s.wantsMeasure($0) }
            guard !s.pendingMeasure.isEmpty else {
                s.measureWorker = false
                return nil
            }
            let url = s.pendingMeasure.removeFirst()
            s.measuring = url
            return url
        }
    }

    /// Ganho da faixa atual, fora da thread principal (ler tags e o cache de medidas toca no disco).
    private func refreshGain() {
        utility.async { [weak self] in self?.applyGain() }
    }

    /// Correção de Som (medida, ou estimada pelas tags) ou ReplayGain das tags.
    private func applyGain() {
        let (url, mode, clip, correction, target) = state.withLock {
            ($0.current, $0.mode, $0.preventClipping, $0.correction, $0.target)
        }
        guard let url else { return }
        let tags = replayGain(for: url)
        let linear: Double
        if correction {
            let info = LoudnessAnalyzer.shared.cached(url) ?? SoundCorrection.estimate(from: tags)
            linear = info.map { SoundCorrection.linearGain(target: target, loudness: $0) } ?? 1
        } else {
            linear = ReplayGainMath.linearGain(mode: mode, info: tags, preventClipping: clip)
        }
        // A faixa pode ter mudado durante a leitura: o pedido seguinte cuida da nova.
        guard state.withLock({ $0.current == url }) else { return }
        chain.setGain(linear: Float(linear))
    }

    // MARK: AudioPlayer.Delegate

    public func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: PCMDecoding?) {
        let id = nowPlaying.map { ObjectIdentifier($0 as AnyObject) }
        let (url, fromQueue) = state.withLock { s -> (URL?, Bool) in
            guard let id, let url = s.tokens[id] else { return (nil, false) }
            s.current = url
            return (url, id != s.startToken)
        }
        if url != nil { refreshGain() }
        DispatchQueue.main.async { [weak self] in
            self?.onNowPlayingChanged?(url)
            self?.onTrackChanged?(url, fromQueue)
        }
    }

    /// Decoder terminou: libera só o token dele (limpar todos apagava o de uma faixa recém-pedida).
    public func audioPlayer(_ audioPlayer: AudioPlayer, renderingComplete decoder: PCMDecoding) {
        releaseToken(of: decoder)
    }

    public func audioPlayer(_ audioPlayer: AudioPlayer, decoderCanceled decoder: PCMDecoding,
                            framesRendered: AVAudioFramePosition) {
        releaseToken(of: decoder)
    }

    /// Arquivo que não abriu ou falhou no meio: o SFB avisa aqui, não em encounteredError.
    public func audioPlayer(_ audioPlayer: AudioPlayer, decodingAborted decoder: PCMDecoding, error: Error,
                            framesRendered: AVAudioFramePosition) {
        let url = releaseToken(of: decoder)
        let message = error.localizedDescription
        let generation = state.withLock { $0.generation }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state.withLock({ $0.generation }) == generation else { return }
            // O SFB já tirou o decoder; sem nada tocando, a reprodução acabou (e o engine parou).
            let ended = self.player.nowPlaying == nil || !self.player.isPlaying
            if let handler = self.onDecodingFailed {
                handler(url, message, ended)
            } else {
                self.onError?(message)
            }
        }
    }

    @discardableResult
    private func releaseToken(of decoder: PCMDecoding) -> URL? {
        let id = ObjectIdentifier(decoder as AnyObject)
        return state.withLock { $0.tokens.removeValue(forKey: id) }
    }

    public func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        let generation = state.withLock { $0.generation }
        DispatchQueue.main.async { [weak self] in
            // Um play() feito depois deste fim não pode ser parado por ele.
            guard let self, self.state.withLock({ $0.generation }) == generation else { return }
            self.onEndOfAudio?()
        }
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
        // O SFB só religa mixer -> saída e reinicia o engine; o tap no limitador continua instalado.
        let rate = audioPlayer.outputNode.outputFormat(forBus: 0).sampleRate
        DispatchQueue.main.async { [weak self] in self?.onConfigurationChange?(rate) }
    }
}
