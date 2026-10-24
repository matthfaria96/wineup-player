import Foundation
import os
import WineupCore

/// Chaves de medição lidas do ambiente (nada liga sem elas).
enum Measure {
    private static let env = ProcessInfo.processInfo.environment
    /// WINEUP_HANG_LOG=<arquivo>: vigia de travadas da thread principal.
    static let hangLogPath = env["WINEUP_HANG_LOG"]
    /// WINEUP_STRESS=1: roteiro de carga depois da abertura (sem som, sem teclas de mídia).
    static let stress = env["WINEUP_STRESS"] != nil
    /// WINEUP_MUTE=1 (teste de reprodução): volume zero e nada de sessão ou volume gravados nas preferências.
    static let mute = env["WINEUP_MUTE"] != nil || stress
    /// Pasta com arquivos reais para o roteiro (abrir 5 mil arquivos, Metadados).
    static let stressFiles = env["WINEUP_STRESS_FILES"]
    /// WINEUP_STRESS_ONLY=metadata|files: só essa parte do roteiro (depois da abertura).
    static let stressOnly = env["WINEUP_STRESS_ONLY"].flatMap { $0.isEmpty ? nil : $0 }
    static let stressShots = env["WINEUP_STRESS_SHOTS"].flatMap { $0.isEmpty ? nil : $0 }
    /// Espera antes do roteiro (s), para ligar um profiler no processo.
    static let stressDelay = env["WINEUP_STRESS_DELAY"].flatMap(Double.init) ?? 0
    static let signposter = OSSignposter(subsystem: "app.wineup.player", category: .pointsOfInterest)
}

/// Vigia da thread principal: uma thread de fundo manda um bloco para a principal a cada ~25 ms
/// e mede quanto ele demorou a rodar. Atrasos de 80 ms ou mais viram uma linha no log,
/// com o passo do roteiro em andamento. Desligado (sem WINEUP_HANG_LOG), não cria nada.
final class HangWatchdog: @unchecked Sendable {
    static let shared: HangWatchdog? = Measure.hangLogPath.map(HangWatchdog.init(path:))

    static let threshold = 80.0
    private static let interval: useconds_t = 25_000

    private let lock = NSLock()
    private let handle: FileHandle?
    private var step = "abertura"
    private var events: [HangEvent] = []

    private init(path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
    }

    func start() {
        let thread = Thread { [self] in loop() }
        thread.name = "wineup.hang-watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Passo atual do roteiro (as travadas seguintes são contadas nele).
    func setStep(_ name: String) {
        lock.withLock { step = name }
        write("passo\t\(name)")
    }

    func allEvents() -> [HangEvent] { lock.withLock { events } }

    func write(_ line: String) {
        lock.withLock { handle?.write(Data((line + "\n").utf8)) }
    }

    private func loop() {
        while true {
            let label = lock.withLock { step }
            let sent = ProcessInfo.processInfo.systemUptime
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { done.signal() }
            done.wait()
            let ms = (ProcessInfo.processInfo.systemUptime - sent) * 1000
            if ms >= Self.threshold {
                lock.withLock { events.append(HangEvent(step: label, milliseconds: ms)) }
                write(String(format: "travada\t%.0f ms\t%@", ms, label))
            }
            usleep(Self.interval)
        }
    }
}
