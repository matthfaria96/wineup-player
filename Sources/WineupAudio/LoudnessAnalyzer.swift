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
    private struct Store { var loaded = false; var entries: [String: Entry] = [:]; var saveScheduled = false }

    /// Intervalo que junta várias medições numa gravação só do loudness.json.
    static let saveDelay: TimeInterval = 1

    private let storeURL: URL
    private let store = OSAllocatedUnfairLock(initialState: Store())
    /// Carregar o loudness.json uma vez só, mesmo com várias threads chegando juntas.
    private let loadLock = NSLock()
    private let saveQueue = DispatchQueue(label: "wineup.loudness.save", qos: .utility)

    /// Não lê o disco aqui: o cache carrega no primeiro uso (chame `prewarm` fora da thread principal).
    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Wineup", isDirectory: true)) {
        storeURL = directory.appendingPathComponent("loudness.json")
    }

    /// Carrega o cache do disco agora. Lento: chame fora da thread principal.
    public func prewarm() { ensureLoaded() }

    /// Medida já guardada (e o arquivo não mudou desde então). Lê o disco: evite a thread principal.
    public func cached(_ url: URL) -> LoudnessInfo? {
        guard let stamp = Self.stamp(url) else { return nil }
        ensureLoaded()
        return store.withLock { s in
            guard let e = s.entries[url.path], e.size == stamp.size, e.modified == stamp.modified else { return nil }
            return e.info
        }
    }

    /// Mede (ou devolve do cache). Lento para arquivos grandes: chame fora da thread principal.
    /// `isCancelled` interrompe a leitura; medida cancelada ou com erro de leitura não é guardada.
    public func measure(_ url: URL, isCancelled: () -> Bool = { false }) -> LoudnessInfo? {
        if let hit = cached(url) { return hit }
        guard let stamp = Self.stamp(url) else { return nil }
        while true {
            switch Self.analyze(url, isCancelled: isCancelled) {
            case .measured(let info):
                store.withLock { $0.entries[url.path] = Entry(size: stamp.size, modified: stamp.modified, info: info) }
                scheduleSave()
                return info
            case .yielded:
                // A forma de onda passou na frente: recomeça depois dela.
                continue
            case .failed, .cancelled:
                return nil
            }
        }
    }

    public var measuredCount: Int {
        ensureLoaded()
        return store.withLock { $0.entries.count }
    }

    /// Grava já o que estiver pendente (testes e saída do app).
    public func saveNow() {
        saveQueue.sync { self.write() }
    }

    private func ensureLoaded() {
        if store.withLock({ $0.loaded }) { return }
        loadLock.lock()
        defer { loadLock.unlock() }
        if store.withLock({ $0.loaded }) { return }
        let saved = (try? Data(contentsOf: storeURL)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        // Arquivos apagados (testes, temporários) saem do cache: um stat por entrada, só aqui.
        let alive = saved.filter { FileManager.default.fileExists(atPath: $0.key) }
        store.withLock { s in
            // Medidas feitas antes do carregamento valem mais que as do disco.
            s.entries = alive.merging(s.entries) { _, new in new }
            s.loaded = true
        }
        if alive.count < saved.count { scheduleSave() }
    }

    /// Junta as medições de um intervalo numa gravação só (antes regravava o cache inteiro a cada música).
    private func scheduleSave() {
        let first = store.withLock { s -> Bool in
            defer { s.saveScheduled = true }
            return !s.saveScheduled
        }
        guard first else { return }
        saveQueue.asyncAfter(deadline: .now() + Self.saveDelay) { [weak self] in self?.write() }
    }

    private func write() {
        let (pending, snapshot) = store.withLock { s -> (Bool, [String: Entry]) in
            defer { s.saveScheduled = false }
            return (s.saveScheduled, s.entries)
        }
        guard pending else { return }
        let url = storeURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    private static func stamp(_ url: URL) -> (size: Int64, modified: Double)? {
        guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = v.fileSize, let date = v.contentModificationDate else { return nil }
        return (Int64(size), date.timeIntervalSince1970)
    }

    enum Analysis: Equatable { case measured(LoudnessInfo), failed, cancelled, yielded }

    /// Mede o volume integrado (BS.1770) decodificando o arquivo inteiro.
    static func analyze(_ url: URL, isCancelled: () -> Bool = { false }) -> Analysis {
        var meter: LoudnessMeter?
        let outcome = AudioFileReader.read(url, priority: .background, isCancelled: isCancelled) { planar, sampleRate in
            if meter == nil { meter = LoudnessMeter(sampleRate: sampleRate, channels: planar.count) }
            meter?.process(planar)
        }
        switch outcome {
        case .finished:
            guard let meter, let lufs = meter.integrated() else { return .failed }
            return .measured(LoudnessInfo(integrated: lufs, peak: meter.peak))
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .yielded: return .yielded
        }
    }
}

/// Lê um arquivo de áudio inteiro em blocos, já em Float32 não intercalado (até 2 canais).
/// Uma leitura por vez em todo o app (forma de onda e medição de volume): decodificadores como o do MP3
/// (mpg123) não aguentam várias aberturas simultâneas fora do player, e trocar de música rápido empilhava leituras.
/// A forma de onda (interativa) passa na frente: a medição em segundo plano para e recomeça depois.
enum AudioFileReader {
    enum Priority { case interactive, background }
    enum Outcome: Equatable {
        /// Leu até o fim.
        case finished
        /// Não abriu ou deu erro no meio (o resultado parcial não vale).
        case failed
        case cancelled
        /// Parou para uma leitura interativa; pode tentar de novo.
        case yielded
    }

    private static let lock = NSLock()
    /// Leituras interativas esperando a vez.
    private static let interactiveWaiting = OSAllocatedUnfairLock(initialState: 0)
    /// Formatos que o Core Audio lê sozinho; os outros (Ogg, Opus, APE...) passam pelo SFB.
    private static let coreAudioTypes: Set<String> = ["mp3", "m4a", "aac", "mp4", "wav", "aif", "aiff", "aifc", "caf", "flac", "alac"]

    /// Chama `body` para cada bloco decodificado. false se não abriu, deu erro ou foi cancelada.
    @discardableResult
    static func read(_ url: URL, isCancelled: () -> Bool = { false },
                     _ body: ([UnsafeBufferPointer<Float>], Double) -> Void) -> Bool {
        read(url, priority: .interactive, isCancelled: isCancelled, body) == .finished
    }

    static func read(_ url: URL, priority: Priority, isCancelled: () -> Bool,
                     _ body: ([UnsafeBufferPointer<Float>], Double) -> Void) -> Outcome {
        let interactive = priority == .interactive
        if interactive {
            interactiveWaiting.withLock { $0 += 1 }
        } else {
            // Não disputa o lock com uma leitura interativa que está esperando.
            while interactiveWaiting.withLock({ $0 > 0 }) {
                if isCancelled() { return .cancelled }
                usleep(20_000)
            }
        }
        lock.lock()
        if interactive { interactiveWaiting.withLock { $0 -= 1 } }
        defer { lock.unlock() }
        func stop() -> Outcome? {
            if isCancelled() { return .cancelled }
            if !interactive, interactiveWaiting.withLock({ $0 > 0 }) { return .yielded }
            return nil
        }
        if let early = stop() { return early }
        if coreAudioTypes.contains(url.pathExtension.lowercased()), let outcome = readWithCoreAudio(url, stop, body) {
            return outcome
        }
        return readWithSFB(url, stop, body)
    }

    /// nil se o Core Audio não abriu o arquivo (aí tenta o SFB).
    private static func readWithCoreAudio(_ url: URL, _ stop: () -> Outcome?,
                                          _ body: ([UnsafeBufferPointer<Float>], Double) -> Void) -> Outcome? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else { return nil }
        while true {
            if let early = stop() { return early }
            // No fim o AVAudioFile lança erro em vez de devolver 0 quadros: confere a posição antes.
            if file.framePosition >= file.length { return .finished }
            do { try file.read(into: buffer) } catch { return .failed }
            guard buffer.frameLength > 0 else { return .finished }
            guard let data = buffer.floatChannelData else { return .failed }
            let frames = Int(buffer.frameLength)
            let channels = min(Int(format.channelCount), 2)
            body((0..<channels).map { UnsafeBufferPointer(start: data[$0], count: frames) }, format.sampleRate)
        }
    }

    private static func readWithSFB(_ url: URL, _ stop: () -> Outcome?,
                                    _ body: ([UnsafeBufferPointer<Float>], Double) -> Void) -> Outcome {
        guard let decoder = try? AudioDecoder(url: url), (try? decoder.open()) != nil else { return .failed }
        defer { try? decoder.close() }
        let source = decoder.processingFormat
        guard let target = AVAudioFormat(standardFormatWithSampleRate: source.sampleRate,
                                         channels: min(source.channelCount, 2)) else { return .failed }
        let converter = source == target ? nil : AVAudioConverter(from: source, to: target)
        let chunk: AVAudioFrameCount = 65_536
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: chunk),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: chunk) else { return .failed }
        while true {
            if let early = stop() { return early }
            do { try decoder.decode(into: input, length: chunk) } catch { return .failed }
            guard input.frameLength > 0 else { return .finished }
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
            guard let data = buffer.floatChannelData else { return .failed }
            let frames = Int(buffer.frameLength)
            body((0..<Int(buffer.format.channelCount)).map { UnsafeBufferPointer(start: data[$0], count: frames) },
                 target.sampleRate)
        }
    }

    /// Só para testes: simula uma leitura interativa esperando a vez.
    static func setInteractiveWaitingForTesting(_ delta: Int) {
        interactiveWaiting.withLock { $0 += delta }
    }
}
