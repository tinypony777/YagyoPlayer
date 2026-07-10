import AVFoundation
import Foundation

@MainActor
final class LegacyAudioPlayerPlaybackBackend: AudioPlaybackBackend {
    var onEvent: (@MainActor @Sendable (AudioPlaybackBackendEvent) -> Void)?

    private var audioPlayer: AVAudioPlayer?
    private var loadedTrackID: AudioTrack.ID?
    private var scheduleGeneration: UInt64 = 0
    private var storedVolume: Float = 0.88

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

    var volume: Float {
        get { storedVolume }
        set {
            storedVolume = newValue
            audioPlayer?.volume = newValue
        }
    }

    func load(url: URL, trackID: AudioTrack.ID) throws {
        let player = try AVAudioPlayer(contentsOf: url)
        player.volume = storedVolume
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
        guard let audioPlayer else { return }
        audioPlayer.currentTime = min(max(seconds, 0), audioPlayer.duration)
        if let loadedTrackID {
            advanceSchedule(for: loadedTrackID)
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        loadedTrackID = nil
        scheduleGeneration += 1
        currentSchedule = nil
    }

    func rebuildAfterConfigurationChange() async throws {
        guard let loadedTrackID else { return }
        advanceSchedule(for: loadedTrackID)
    }

    func prepareToResumeAfterInterruption() async throws {}

    func realtimeAnalysisSnapshot() -> RealtimeAnalysisSnapshot {
        guard let audioPlayer, audioPlayer.isPlaying, audioPlayer.numberOfChannels > 0 else {
            return .unavailable
        }

        audioPlayer.updateMeters()
        var decibels = -160.0
        for channel in 0..<audioPlayer.numberOfChannels {
            decibels = max(decibels, Double(audioPlayer.averagePower(forChannel: channel)))
        }
        let normalized = min(max((decibels + 48) / 48, 0), 1)
        return RealtimeAnalysisSnapshot(
            level: normalized,
            momentaryLUFS: nil,
            shortTermLUFS: nil,
            isSilent: false,
            onsetStrength: 0,
            onsetSequence: 0,
            droppedAnalysisBlockCount: 0,
            hasDiscontinuity: false
        )
    }

    private func advanceSchedule(for trackID: AudioTrack.ID) {
        scheduleGeneration += 1
        currentSchedule = PlaybackScheduleIdentity(trackID: trackID, generation: scheduleGeneration)
    }
}
