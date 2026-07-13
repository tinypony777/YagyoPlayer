import Foundation

@testable import YagyoPlayer

@MainActor
class FakeAudioPlaybackBackend: AudioPlaybackBackend {
    private(set) var currentSchedule: PlaybackScheduleIdentity?
    var duration: TimeInterval
    var position: TimeInterval
    private(set) var isPlaying = false
    var outputVolume: Float = 0.88
    var meterLevel: Double?

    private(set) var loadCalls: [(url: URL, trackID: AudioTrack.ID)] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var seekCalls: [TimeInterval] = []
    private(set) var stopCallCount = 0

    var loadError: Error?
    var loadErrorAfterMutation: Error?
    var playError: Error?
    var seekError: Error?
    var suppressSchedulePublicationOnLoad = false
    var suppressSchedulePublicationOnSeek = false

    private var generation: UInt64 = 0
    private var loadedTrackID: AudioTrack.ID?

    init(duration: TimeInterval = 0, position: TimeInterval = 0) {
        self.duration = duration
        self.position = position
    }

    func load(url: URL, trackID: AudioTrack.ID) throws {
        if let loadError { throw loadError }
        generation &+= 1
        loadedTrackID = trackID
        if !suppressSchedulePublicationOnLoad {
            currentSchedule = PlaybackScheduleIdentity(trackID: trackID, generation: generation)
        }
        position = 0
        isPlaying = false
        loadCalls.append((url, trackID))
        if let loadErrorAfterMutation { throw loadErrorAfterMutation }
    }

    func play() throws {
        if let playError { throw playError }
        guard loadedTrackID != nil else {
            throw AudioPlaybackBackendError.noTrackLoaded
        }
        playCallCount += 1
        isPlaying = true
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }

    func seek(to seconds: TimeInterval) throws {
        if let seekError { throw seekError }
        guard let loadedTrackID else {
            throw AudioPlaybackBackendError.noTrackLoaded
        }
        generation &+= 1
        position = seconds
        seekCalls.append(seconds)
        if !suppressSchedulePublicationOnSeek {
            currentSchedule = PlaybackScheduleIdentity(
                trackID: loadedTrackID,
                generation: generation
            )
        }
    }

    func stop() {
        generation &+= 1
        stopCallCount += 1
        loadedTrackID = nil
        currentSchedule = nil
        isPlaying = false
        position = 0
    }

    func normalizedMeterLevel() -> Double? {
        meterLevel
    }
}

@MainActor
final class FakeFixedEQAuditionPlaybackBackend: FakeAudioPlaybackBackend,
    FixedEQAuditionControlling
{
    private(set) var fixedEQAuditionState: FixedEQAuditionState = .waitingForTrack
    private(set) var requestedModes: [FixedEQAuditionMode] = []
    private(set) var resetCallCount = 0
    var auditionError: Error?

    override func load(url: URL, trackID: AudioTrack.ID) throws {
        try super.load(url: url, trackID: trackID)
        fixedEQAuditionState = Self.state(mode: .original)
    }

    override func stop() {
        super.stop()
        fixedEQAuditionState = .waitingForTrack
    }

    func requestFixedEQAuditionMode(_ mode: FixedEQAuditionMode) throws {
        if let auditionError { throw auditionError }
        guard currentSchedule != nil else {
            throw AudioPlaybackBackendError.noTrackLoaded
        }
        requestedModes.append(mode)
        fixedEQAuditionState = Self.state(mode: mode)
    }

    func resetFixedEQAudition() throws {
        if let auditionError { throw auditionError }
        resetCallCount += 1
        fixedEQAuditionState = currentSchedule == nil
            ? .waitingForTrack
            : Self.state(mode: .original)
    }

    private static func state(mode: FixedEQAuditionMode) -> FixedEQAuditionState {
        FixedEQAuditionState(
            availability: .ready,
            requestedMode: mode,
            appliedMode: mode,
            isSwitching: false,
            appliesOnNextPlay: false,
            failureMessage: nil
        )
    }
}
