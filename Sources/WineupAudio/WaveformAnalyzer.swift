import Foundation
import WineupCore
import os

/// Forma de onda real de uma música: o volume (RMS) de cada trecho, lido do arquivo uma vez e guardado em memória.
public final class WaveformAnalyzer: @unchecked Sendable {
    public static let shared = WaveformAnalyzer()
    /// Quantos trechos a música é dividida (a tela agrupa conforme a largura disponível).
    public static let bucketCount = 600

    private let cache = OSAllocatedUnfairLock(initialState: [String: [Float]]())

    /// Volume em dBFS de cada trecho. Lento (decodifica o arquivo todo): chame fora da thread principal.
    /// `isCancelled` interrompe a leitura (ex.: o usuário já trocou de música); nada é guardado nesse caso.
    public func levels(_ url: URL, isCancelled: () -> Bool = { false }) -> [Float]? {
        let key = Self.key(url)
        if let hit = cache.withLock({ $0[key] }) { return hit }
        guard let result = Self.analyze(url, isCancelled: isCancelled) else { return nil }
        cache.withLock { c in
            if c.count > 200 { c.removeAll() }
            c[key] = result
        }
        return result
    }

    static func key(_ url: URL) -> String {
        let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "\(url.path)|\(v?.fileSize ?? 0)|\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    /// Soma de quadrados por janela de ~50 ms; depois agrupa em `bucketCount` trechos e converte para dB.
    static func analyze(_ url: URL, isCancelled: () -> Bool = { false }) -> [Float]? {
        var windows: [Float] = []
        var acc: Float = 0, count = 0, window = 2_205
        let ok = AudioFileReader.read(url, isCancelled: isCancelled) { planar, rate in
            window = max(1, Int(rate / 20))
            let frames = planar.first?.count ?? 0
            for i in 0..<frames {
                var v: Float = 0
                for ch in planar { v += ch[i] * ch[i] }
                acc += v / Float(planar.count)
                count += 1
                if count == window { windows.append(acc / Float(count)); acc = 0; count = 0 }
            }
        }
        if count > 0 { windows.append(acc / Float(count)) }
        guard ok, !windows.isEmpty else { return nil }
        return Waveform.buckets(meanSquares: windows, count: bucketCount)
    }
}
