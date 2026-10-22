import Foundation
import SFBAudioEngine
import WineupCore

/// Lê as tags ReplayGain de um arquivo. Somente leitura: nunca grava no arquivo.
/// Opus: o SFB 0.14 não converte R128_TRACK_GAIN/R128_ALBUM_GAIN; lemos dos campos extras
/// e convertemos (R128Gain). Valores não confiáveis são saneados depois por `ReplayGainMath`.
public enum ReplayGainReader {
    public static func read(_ url: URL) -> ReplayGainInfo {
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url) else {
            return ReplayGainInfo()
        }
        let m = file.metadata
        let extra = (m.additionalMetadata ?? [:]) as [AnyHashable: Any]
        return ReplayGainInfo(
            trackGain: m.replayGainTrackGain ?? R128Gain.replayGainDB(fromTag: R128Gain.lookup("R128_TRACK_GAIN", in: extra)),
            trackPeak: m.replayGainTrackPeak,
            albumGain: m.replayGainAlbumGain ?? R128Gain.replayGainDB(fromTag: R128Gain.lookup("R128_ALBUM_GAIN", in: extra)),
            albumPeak: m.replayGainAlbumPeak
        )
    }
}
