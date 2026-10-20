import Foundation
import SFBAudioEngine
import WineupCore

/// Lê as tags ReplayGain de um arquivo. Somente leitura: nunca grava no arquivo.
/// Limitação: Opus R128 (R128_TRACK_GAIN) não é lido pelo SFB 0.14; faixas Opus ficam
/// sem ganho (1,0). Valores não confiáveis são saneados depois por `ReplayGainMath`.
public enum ReplayGainReader {
    public static func read(_ url: URL) -> ReplayGainInfo {
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url) else {
            return ReplayGainInfo()
        }
        let m = file.metadata
        return ReplayGainInfo(
            trackGain: m.replayGainTrackGain,
            trackPeak: m.replayGainTrackPeak,
            albumGain: m.replayGainAlbumGain,
            albumPeak: m.replayGainAlbumPeak
        )
    }
}
