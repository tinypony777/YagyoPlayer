import Foundation
@testable import YagyoPlayer

@MainActor
final class FakeAudioPlaybackBackend: AudioPlaybackBackend {
    var onEvent: (@MainActor @Sendable (AudioPlaybackBackendEvent) -> Void)?
    private(set) var currentSchedule: PlaybackScheduleIdentity?
    var duration: TimeInterval
    var position: TimeInterval
    private(set) var isPlaying = false
    var volume: Float = 0.88
    var snapshot = RealtimeAnalysisSnapshot.unavailable

    private(set) var loadCalls: [(url: URL, trackID: AudioTrack.ID)] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var seekCalls: [TimeInterval] = []
    private(set) var stopCallCount = 0
    private(set) var rebuildAfterConfigurationChangeCallCount = 0
    private(set) var prepareToResumeAfterInterruptionCallCount = 0

    var loadError: Error?
    var playError: Error?
    var seekError: Error?
    var rebuildError: Error?
    var interruptionPreparationError: Error?

    private var generation: UInt64 = 0
    private var loadedTrackID: AudioTrack.ID?
    private var shouldSuspendRebuild = false
    private var rebuildContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendInterruptionPreparation = false
    private var interruptionPreparationContinuation: CheckedContinuation<Void, Never>?

    init(duration: TimeInterval = 0, position: TimeInterval = 0) {
        self.duration = duration
        self.position = position
    }

    func load(url: URL, trackID: AudioTrack.ID) throws {
        if let loadError {
            throw loadError
        }
        generation += 1
        loadedTrackID = trackID
        currentSchedule = PlaybackScheduleIdentity(trackID: trackID, generation: generation)
        position = 0
        isPlaying = false
        loadCalls.append((url, trackID))
    }

    func play() throws {
        if let playError {
            throw playError
        }
        playCallCount += 1
        isPlaying = true
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }

    func seek(to seconds: TimeInterval) throws {
        if let seekError {
            throw seekError
        }
        generation += 1
        position = seconds
        seekCalls.append(seconds)
        if let loadedTrackID {
            currentSchedule = PlaybackScheduleIdentity(trackID: loadedTrackID, generation: generation)
        }
    }

    func stop() {
        generation += 1
        stopCallCount += 1
        isPlaying = false
        position = 0
        currentSchedule = nil
    }

    func rebuildAfterConfigurationChange() async throws {
        rebuildAfterConfigurationChangeCallCount += 1
        if shouldSuspendRebuild {
            await withCheckedContinuation { continuation in
                rebuildContinuation = continuation
            }
        }
        if let rebuildError {
            throw rebuildError
        }
        generation += 1
        if let loadedTrackID {
            currentSchedule = PlaybackScheduleIdentity(trackID: loadedTrackID, generation: generation)
        }
    }

    func prepareToResumeAfterInterruption() async throws {
        prepareToResumeAfterInterruptionCallCount += 1
        if shouldSuspendInterruptionPreparation {
            await withCheckedContinuation { continuation in
                interruptionPreparationContinuation = continuation
            }
        }
        if let interruptionPreparationError {
            throw interruptionPreparationError
        }
    }

    func realtimeAnalysisSnapshot() -> RealtimeAnalysisSnapshot {
        snapshot
    }

    func emit(_ event: AudioPlaybackBackendEvent) {
        onEvent?(event)
    }

    func suspendRebuild() async {
        shouldSuspendRebuild = true
    }

    func finishRebuild() {
        shouldSuspendRebuild = false
        rebuildContinuation?.resume()
        rebuildContinuation = nil
    }

    func suspendInterruptionPreparation() async {
        shouldSuspendInterruptionPreparation = true
    }

    func finishInterruptionPreparation() {
        shouldSuspendInterruptionPreparation = false
        interruptionPreparationContinuation?.resume()
        interruptionPreparationContinuation = nil
    }
}
