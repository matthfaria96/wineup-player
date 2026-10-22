import Foundation

/// Ganho R128 do Opus (R128_TRACK_GAIN / R128_ALBUM_GAIN): inteiro Q7.8 em dB, referência
/// -23 LUFS. O ReplayGain usa -18 LUFS, então o ganho equivalente é valor/256 + 5 dB.
public enum R128Gain {
    public static func replayGainDB(fromTag value: String?) -> Double? {
        guard let text = value?.trimmingCharacters(in: .whitespaces), let q78 = Int(text),
              (-32768...32767).contains(q78) else { return nil }
        return Double(q78) / 256 + 5
    }

    /// Procura a chave sem diferenciar maiúsculas (os comentários Vorbis variam).
    public static func lookup(_ key: String, in metadata: [AnyHashable: Any]) -> String? {
        for (k, v) in metadata where (k as? String)?.uppercased() == key { return "\(v)" }
        return nil
    }
}
