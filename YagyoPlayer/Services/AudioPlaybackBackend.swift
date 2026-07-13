import Foundation

/// Identifies the exact render schedule, not only its source track. Every successful
/// load or seek publishes a new generation; a failed operation preserves the prior one.
struct PlaybackScheduleIdentity: Equatable, Hashable, Sendable {
    let trackID: AudioTrack.ID
    let generation: UInt64
}

enum AudioPlaybackBackendError: LocalizedError {
    case noTrackLoaded
    case playbackCouldNotStart
    case scheduleIdentityMismatch

    var errorDescription: String? {
        switch self {
        case .noTrackLoaded:
            return "No track is loaded yet."
        case .playbackCouldNotStart:
            return "Playback could not start."
        case .scheduleIdentityMismatch:
            return "The playback backend did not commit the requested track."
        }
    }
}

enum FixedEQAuditionMode: Equatable, Sendable {
    case original
    case fixedEQ
}

enum FixedEQAuditionAvailability: Equatable, Sendable {
    /// The active backend deliberately has no Fixed EQ preview capability.
    case unsupported
    /// The preview backend is active, but no playable track has been committed yet.
    case waitingForTrack
    case ready
}

/// Control-side view of the optional same-track Fixed EQ preview. This state never
/// reuses the two-track 狐火の帳 A/B session or its loudness multiplier.
struct FixedEQAuditionState: Equatable, Sendable {
    let availability: FixedEQAuditionAvailability
    let requestedMode: FixedEQAuditionMode
    let appliedMode: FixedEQAuditionMode
    let isSwitching: Bool
    let appliesOnNextPlay: Bool
    let failureMessage: String?

    static let unsupported = FixedEQAuditionState(
        availability: .unsupported,
        requestedMode: .original,
        appliedMode: .original,
        isSwitching: false,
        appliesOnNextPlay: false,
        failureMessage: nil
    )

    static let waitingForTrack = FixedEQAuditionState(
        availability: .waitingForTrack,
        requestedMode: .original,
        appliedMode: .original,
        isSwitching: false,
        appliesOnNextPlay: false,
        failureMessage: nil
    )
}

/// Optional capability implemented only by the iOS 27 device-preview backend.
/// PlaybackController owns presentation and route policy; the backend owns the
/// render generation acknowledgement.
@MainActor
protocol FixedEQAuditionControlling: AnyObject {
    var fixedEQAuditionState: FixedEQAuditionState { get }

    func requestFixedEQAuditionMode(_ mode: FixedEQAuditionMode) throws
    func resetFixedEQAudition() throws
}

/// Playback mechanism boundary. Policy such as queue order, loudness matching,
/// interruptions, Now Playing, and playback statistics remains in PlaybackController.
@MainActor
protocol AudioPlaybackBackend: AnyObject {
    var currentSchedule: PlaybackScheduleIdentity? { get }
    var duration: TimeInterval { get }
    var position: TimeInterval { get }
    var isPlaying: Bool { get }
    var outputVolume: Float { get set }

    /// Must be failure-atomic: until this returns successfully, the prior schedule
    /// remains usable and `currentSchedule` keeps its prior identity.
    func load(url: URL, trackID: AudioTrack.ID) throws
    func play() throws
    func pause()
    /// Must publish a new schedule generation on success and preserve it on failure.
    func seek(to seconds: TimeInterval) throws
    func stop()

    /// Normalized 0...1 observation for the parade visual signal. This is not a DSP input.
    func normalizedMeterLevel() -> Double?
}
