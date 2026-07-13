import AVFoundation
import Foundation

/// The existing production playback mechanism, kept as the default backend while the
/// explicit Fixed EQ preview path is developed independently.
@MainActor
final class LegacyAudioPlayerPlaybackBackend: AudioPlaybackBackend {
    private var audioPlayer: AVAudioPlayer?
    private var loadedTrackID: AudioTrack.ID?
    private var scheduleGeneration: UInt64 = 0
    private var storedOutputVolume: Float = 0.88

    private(set) var currentSchedule: PlaybackScheduleIdentity?

    var duration: TimeInterval {
        audioPlayer?.duration ?? 0
    }

    var position: TimeInterval {
        audioPlayer?.currentTime ?? 0
    }

    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }

    var outputVolume: Float {
        get { storedOutputVolume }
        set {
            storedOutputVolume = newValue
            audioPlayer?.volume = newValue
        }
    }

    func load(url: URL, trackID: AudioTrack.ID) throws {
        let player = try AVAudioPlayer(contentsOf: url)
        player.volume = storedOutputVolume
        player.isMeteringEnabled = true
        player.prepareToPlay()

        audioPlayer = player
        loadedTrackID = trackID
        advanceSchedule(for: trackID)
    }

    func play() throws {
        guard let audioPlayer else {
            throw AudioPlaybackBackendError.noTrackLoaded
        }
        guard audioPlayer.play() else {
            throw AudioPlaybackBackendError.playbackCouldNotStart
        }
    }

    func pause() {
        audioPlayer?.pause()
    }

    func seek(to seconds: TimeInterval) throws {
        guard let audioPlayer else {
            throw AudioPlaybackBackendError.noTrackLoaded
        }
        audioPlayer.currentTime = min(max(seconds, 0), audioPlayer.duration)
        if let loadedTrackID {
            advanceSchedule(for: loadedTrackID)
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        loadedTrackID = nil
        scheduleGeneration &+= 1
        currentSchedule = nil
    }

    func normalizedMeterLevel() -> Double? {
        guard let audioPlayer, audioPlayer.numberOfChannels > 0 else {
            return nil
        }
        audioPlayer.updateMeters()

        var decibels = -160.0
        for channel in 0..<audioPlayer.numberOfChannels {
            let channelPower = Double(audioPlayer.averagePower(forChannel: channel))
            guard channelPower.isFinite else { return nil }
            decibels = max(decibels, channelPower)
        }
        return min(max((decibels + 48) / 48, 0), 1)
    }

    private func advanceSchedule(for trackID: AudioTrack.ID) {
        scheduleGeneration &+= 1
        currentSchedule = PlaybackScheduleIdentity(
            trackID: trackID,
            generation: scheduleGeneration
        )
    }
}
