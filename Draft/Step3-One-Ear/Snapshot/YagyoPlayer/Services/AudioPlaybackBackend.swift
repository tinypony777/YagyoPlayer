import Foundation

struct PlaybackScheduleIdentity: Equatable, Hashable, Sendable {
    let trackID: AudioTrack.ID
    let generation: UInt64
}

enum AudioPlaybackBackendEvent: Equatable, Sendable {
    case finished(PlaybackScheduleIdentity)
    case engineConfigurationChanged(PlaybackScheduleIdentity)
}

enum AudioPlaybackBackendError: LocalizedError {
    case noTrackLoaded
    case playbackCouldNotStart

    var errorDescription: String? {
        switch self {
        case .noTrackLoaded:
            return "No track is loaded."
        case .playbackCouldNotStart:
            return "Playback could not start."
        }
    }
}

@MainActor
protocol AudioPlaybackBackend: AnyObject {
    var onEvent: (@MainActor @Sendable (AudioPlaybackBackendEvent) -> Void)? { get set }
    var currentSchedule: PlaybackScheduleIdentity? { get }
    var duration: TimeInterval { get }
    var position: TimeInterval { get }
    var isPlaying: Bool { get }
    var volume: Float { get set }

    func load(url: URL, trackID: AudioTrack.ID) throws
    func play() throws
    func pause()
    func seek(to seconds: TimeInterval) throws
    func stop()
    func rebuildAfterConfigurationChange() async throws
    func prepareToResumeAfterInterruption() async throws
    func realtimeAnalysisSnapshot() -> RealtimeAnalysisSnapshot
}
