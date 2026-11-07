import Foundation
import MediaPlayer
import UIKit

/// Publishes audiobook metadata and routes iOS lock-screen / Control Center commands.
/// A spoken PDF page has no reliable duration, so we intentionally omit a fake seek bar.
@MainActor
final class LockScreenPlayer {
    private let center = MPRemoteCommandCenter.shared()

    func install(
        play: @escaping @MainActor () -> Void,
        pause: @escaping @MainActor () -> Void,
        toggle: @escaping @MainActor () -> Void,
        next: @escaping @MainActor () -> Void,
        previous: @escaping @MainActor () -> Void
    ) {
        center.playCommand.addTarget { _ in
            Task { @MainActor in play() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in previous() }
            return .success
        }
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
        setEnabled(false)
    }

    func setEnabled(_ enabled: Bool) {
        center.playCommand.isEnabled = enabled
        center.pauseCommand.isEnabled = enabled
        center.togglePlayPauseCommand.isEnabled = enabled
        center.nextTrackCommand.isEnabled = enabled
        center.previousTrackCommand.isEnabled = enabled
    }

    func publish(title: String, page: Int, total: Int, isPlaying: Bool, artwork: MPMediaItemArtwork?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "BookVoice · PDF",
            MPMediaItemPropertyAlbumTitle: "Страница \(page + 1) из \(total)",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        setEnabled(false)
    }
}
