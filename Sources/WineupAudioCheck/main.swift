import AVFoundation
import Foundation
import WineupAudio

// Verificação offline do caminho SFB real (render manual, sem som). Deve rodar em release:
// em debug o assert de host time do SFB aborta o render manual.

struct CheckError: Error { let reason: String; init(_ r: String) { reason = r } }

func dB(_ rms: Float) -> Float { 20 * log10(max(rms, 1e-9)) }

/// Adaptador + engine em modo de render manual offline.
final class Harness {
    let adapter = SFBAudioEngineAdapter()
    var engine: AVAudioEngine!
    let buffer: AVAudioPCMBuffer
    var events: [String] = []
    var current: URL?
    var onChange: ((URL?) -> Void)?

    init() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var captured: AVAudioEngine?
        try adapter.withEngine { e in
            e.stop()
            try e.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            captured = e
        }
        engine = captured
        adapter.meter.install(on: engine.mainMixerNode)
        adapter.onNowPlayingChanged = { [weak self] url in
            guard let self else { return }
            self.current = url
            self.events.append(url?.lastPathComponent ?? "nil")
            self.onChange?(url)
        }
        adapter.onEndOfAudio = { [weak self] in self?.events.append("endOfAudio") }
    }

    struct Block { let rmsDB: Float; let left: [Float]; let current: URL?; let meterTime: TimeInterval? }

    /// Renderiza um bloco de 1024 quadros e deixa o decoder assíncrono e a main acompanharem.
    func block() throws -> Block {
        let status = try engine.renderOffline(1024, to: buffer)
        RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        usleep(12_000)
        guard status == .success || status == .insufficientDataFromInputNode || status == .cannotDoInCurrentContext else {
            throw CheckError("renderOffline status \(status.rawValue)")
        }
        let n = Int(buffer.frameLength)
        let left = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: n))
        let rms = n > 0 ? sqrt(left.reduce(0) { $0 + $1 * $1 } / Float(n)) : 0
        return Block(rmsDB: dB(rms), left: left, current: current, meterTime: adapter.meter.snapshot()?.timestamp)
    }

    func blocks(_ count: Int) throws -> [Block] { try (0..<count).map { _ in try block() } }
}

func median(_ v: [Float]) -> Float { v.isEmpty ? -999 : v.sorted()[v.count / 2] }

// MARK: Sequência de quatro formatos (chain + meter)

struct SequenceResult { let medians: [String: Float]; let meterTimes: [String: Set<TimeInterval>]; let events: [String] }

func runSequence(_ fx: FixtureSet) throws -> SequenceResult {
    let tracks = [
        try fx.sine("t1-44k-st.wav", rate: 44_100, channels: 2, seconds: 1),
        try fx.sine("t2-48k-mono.wav", rate: 48_000, channels: 1, seconds: 1),
        try fx.sine("t3-96k-st.wav", rate: 96_000, channels: 2, seconds: 1),
        try fx.sine("t4-44k-st.wav", rate: 44_100, channels: 2, seconds: 1),
    ]
    let h = try Harness()
    h.onChange = { url in
        guard let url, let i = tracks.firstIndex(of: url), i + 1 < tracks.count else { return }
        try? h.adapter.enqueue(tracks[i + 1])
    }
    try h.adapter.play(tracks[0])
    try h.adapter.enqueue(tracks[1])
    var rms: [String: [Float]] = [:]
    var times: [String: Set<TimeInterval>] = [:]
    var done = false
    for _ in 0..<400 where !done {
        let b = try h.block()
        if let name = b.current?.lastPathComponent {
            rms[name, default: []].append(b.rmsDB)
            if let t = b.meterTime { times[name, default: []].insert(t) }
        }
        done = h.events.contains("endOfAudio")
    }
    h.adapter.stop()
    return SequenceResult(medians: rms.mapValues(median), meterTimes: times, events: h.events)
}

func checkChain(_ r: SequenceResult) throws {
    let names = ["t1-44k-st.wav", "t2-48k-mono.wav", "t3-96k-st.wav", "t4-44k-st.wav"]
    for n in names {
        guard let m = r.medians[n] else { throw CheckError("faixa \(n) nunca tocou (eventos \(r.events))") }
        guard m > -40 else { throw CheckError("faixa \(n) com RMS mediano \(m) dB") }
    }
}

func checkMeter(_ r: SequenceResult) throws {
    let names = ["t1-44k-st.wav", "t2-48k-mono.wav", "t3-96k-st.wav", "t4-44k-st.wav"]
    for n in names {
        let count = r.meterTimes[n]?.count ?? 0
        guard count >= 2 else { throw CheckError("tap sem timestamps avançando em \(n) (\(count))") }
    }
}

// MARK: rate

func checkRate(_ fx: FixtureSet) throws {
    let long = try fx.sine("rate.wav", rate: 44_100, channels: 2, seconds: 8)
    for (rate, expected) in [(1.5, 3.0), (0.5, 1.0)] {
        let h = try Harness()
        h.adapter.setRate(rate)
        try h.adapter.play(long)
        _ = try h.blocks(86) // 86 * 1024 quadros ~ 2,0 s de saída
        let t = h.adapter.currentTime
        h.adapter.stop()
        guard abs(t - expected) <= expected * 0.05 else {
            throw CheckError("rate \(rate): currentTime \(t), esperado \(expected) +/-5%")
        }
    }
}

// MARK: gapless

func checkGapless(_ fx: FixtureSet) throws {
    let a = try fx.sine("A.wav", rate: 44_100, channels: 2, seconds: 1)
    let b = try fx.sine("B.wav", rate: 44_100, channels: 2, seconds: 1, startFrame: 44_100)
    let h = try Harness()
    try h.adapter.play(a)
    try h.adapter.enqueue(b)
    var samples: [Float] = []
    for _ in 0..<200 {
        samples += try h.block().left
        if h.events.contains("endOfAudio") { break }
    }
    h.adapter.stop()
    guard let first = samples.firstIndex(where: { abs($0) > 1e-4 }),
          let last = samples.lastIndex(where: { abs($0) > 1e-4 }) else { throw CheckError("sem áudio renderizado") }
    var run = 0, worst = 0
    for s in samples[first...last] {
        run = abs(s) < 1e-6 ? run + 1 : 0
        worst = max(worst, run)
    }
    guard worst <= 16 else { throw CheckError("corrida de \(worst) zeros entre A e B") }
    guard last - first > 70_000 else { throw CheckError("saída curta demais (\(last - first) quadros)") }
    let expected = ["A.wav", "B.wav", "nil", "endOfAudio"]
    guard h.events == expected else { throw CheckError("eventos \(h.events), esperado \(expected)") }
}

// MARK: configchange

func checkConfigChange(_ fx: FixtureSet) throws {
    let long = try fx.sine("cfg.wav", rate: 44_100, channels: 2, seconds: 8)
    let h = try Harness()
    try h.adapter.play(long)
    _ = try h.blocks(20)
    NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: h.engine)
    for _ in 0..<10 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    let tBefore = h.adapter.meter.snapshot()?.timestamp ?? 0
    let after = try h.blocks(30)
    let playing = h.adapter.isPlaying
    let tAfter = h.adapter.meter.snapshot()?.timestamp ?? 0
    h.adapter.stop()
    guard playing else { throw CheckError("isPlaying false após a troca de configuração") }
    let m = median(after.map(\.rmsDB))
    guard m > -40 else { throw CheckError("RMS mediano \(m) dB após a troca") }
    guard tAfter > tBefore else { throw CheckError("tap não avançou após a troca (\(tBefore) -> \(tAfter))") }
}

// MARK: driver

let requested = CommandLine.arguments.dropFirst().first ?? "all"
let known = ["meter", "rate", "chain", "gapless", "configchange", "all"]
guard known.contains(requested) else {
    print("uso: wineup-audiocheck [\(known.joined(separator: "|"))]")
    exit(2)
}

var failed = false
func report(_ name: String, _ body: () throws -> Void) {
    do { try body(); print("PASS \(name)") } catch let e as CheckError {
        print("FAIL \(name): \(e.reason)"); failed = true
    } catch {
        print("FAIL \(name): \(error)"); failed = true
    }
}

do {
    let fx = try FixtureSet()
    defer { fx.cleanup() }
    func wants(_ n: String) -> Bool { requested == "all" || requested == n }

    if wants("chain") || wants("meter") {
        do {
            let seq = try runSequence(fx)
            if wants("chain") { report("chain") { try checkChain(seq) } }
            if wants("meter") { report("meter") { try checkMeter(seq) } }
        } catch {
            for n in ["chain", "meter"] where wants(n) { print("FAIL \(n): \(error)"); failed = true }
        }
    }
    if wants("rate") { report("rate") { try checkRate(fx) } }
    if wants("gapless") { report("gapless") { try checkGapless(fx) } }
    if wants("configchange") { report("configchange") { try checkConfigChange(fx) } }
    fx.cleanup()
} catch {
    print("FAIL setup: \(error)")
    failed = true
}
exit(failed ? 1 : 0)
