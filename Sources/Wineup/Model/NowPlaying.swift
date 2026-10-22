import AppKit
import MediaPlayer

/// Integração com o sistema: "Tocando agora" (Central de Controle) e teclas de mídia.
enum NowPlaying {
    static func attach(_ state: PlayerState) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak state] _ in
            guard let state else { return .commandFailed }
            if !state.isPlaying { state.togglePlay() }
            return .success
        }
        center.pauseCommand.addTarget { [weak state] _ in
            state?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak state] _ in
            state?.togglePlay()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak state] _ in
            state?.step(by: 1)
            return .success
        }
        center.previousTrackCommand.addTarget { [weak state] _ in
            state?.step(by: -1)
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak state] event in
            guard let state, let event = event as? MPChangePlaybackPositionCommandEvent,
                  let duration = state.currentTrack?.duration, duration > 0 else { return .commandFailed }
            state.seek(to: event.positionTime / Double(duration))
            return .success
        }
    }

    static func update(_ state: PlayerState) {
        let info = MPNowPlayingInfoCenter.default()
        guard let track = state.currentTrack else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        let duration = Double(track.duration)
        var dict: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: duration * state.progress,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? state.playbackRate : 0,
        ]
        if let album = track.album { dict[MPMediaItemPropertyAlbumTitle] = album }
        if let image = state.cover {
            dict[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        info.nowPlayingInfo = dict
        info.playbackState = state.isPlaying ? .playing : .paused
    }
}
