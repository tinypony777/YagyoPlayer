import AVFoundation
import XCTest

@testable import YagyoPlayer

@MainActor
@available(iOS 27.0, *)
final class AVAudioEngineFixedEQPlaybackBackendTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() async throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testLoadSeekAndStopPublishExactScheduleState() throws {
        let fileURL = try makeSineFile(named: "schedule.caf", duration: 1)
        let trackID = UUID()
        let backend = AVAudioEngineFixedEQPlaybackBackend()

        XCTAssertEqual(backend.fixedEQAuditionState, .waitingForTrack)
        backend.outputVolume = 0.42
        try backend.load(url: fileURL, trackID: trackID)

        let loadedSchedule = try XCTUnwrap(backend.currentSchedule)
        XCTAssertEqual(loadedSchedule.trackID, trackID)
        XCTAssertEqual(backend.duration, 1, accuracy: 1e-3)
        XCTAssertEqual(backend.position, 0, accuracy: 1e-6)
        XCTAssertFalse(backend.isPlaying)
        XCTAssertEqual(backend.fixedEQAuditionState.availability, .ready)
        XCTAssertEqual(backend.fixedEQAuditionState.requestedMode, .original)
        XCTAssertEqual(backend.fixedEQAuditionState.appliedMode, .original)

        try backend.requestFixedEQAuditionMode(.fixedEQ)
        XCTAssertEqual(backend.fixedEQAuditionState.requestedMode, .fixedEQ)
        XCTAssertEqual(backend.fixedEQAuditionState.appliedMode, .original)
        XCTAssertTrue(backend.fixedEQAuditionState.appliesOnNextPlay)

        try backend.seek(to: 0.25)
        let seekSchedule = try XCTUnwrap(backend.currentSchedule)
        XCTAssertNotEqual(seekSchedule, loadedSchedule)
        XCTAssertEqual(seekSchedule.trackID, trackID)
        XCTAssertEqual(backend.position, 0.25, accuracy: 1 / 48_000)
        XCTAssertEqual(backend.fixedEQAuditionState.requestedMode, .fixedEQ)
        XCTAssertTrue(backend.fixedEQAuditionState.appliesOnNextPlay)

        backend.stop()
        XCTAssertNil(backend.currentSchedule)
        XCTAssertEqual(backend.fixedEQAuditionState, .waitingForTrack)
        XCTAssertEqual(backend.duration, 0)
        XCTAssertEqual(backend.position, 0)
    }

    func testFailedReplacementLoadPreservesPriorGraphAndSchedule() throws {
        let fileURL = try makeSineFile(named: "committed.caf", duration: 0.5)
        let trackID = UUID()
        let backend = AVAudioEngineFixedEQPlaybackBackend()
        try backend.load(url: fileURL, trackID: trackID)
        defer { backend.stop() }
        let committedSchedule = backend.currentSchedule

        XCTAssertThrowsError(
            try backend.load(
                url: temporaryDirectory.appending(path: "missing.caf"),
                trackID: UUID()
            )
        )

        XCTAssertEqual(backend.currentSchedule, committedSchedule)
        XCTAssertEqual(backend.currentSchedule?.trackID, trackID)
        XCTAssertEqual(backend.fixedEQAuditionState.availability, .ready)
    }

    func testInvalidTransitionConfigurationFailsClosedBeforePublishingSchedule() throws {
        let fileURL = try makeSineFile(named: "transition.caf", duration: 0.25)
        let backend = AVAudioEngineFixedEQPlaybackBackend(
            transitionFrameCount: FixedEQTransitionContract.maximumFrameCount + 1
        )

        XCTAssertThrowsError(try backend.load(url: fileURL, trackID: UUID())) { error in
            XCTAssertEqual(
                error as? FixedEQAudioUnitError,
                .invalidTransitionFrames
            )
        }
        XCTAssertNil(backend.currentSchedule)
        XCTAssertEqual(backend.fixedEQAuditionState, .waitingForTrack)
    }

    func testRealtimeGraphAcknowledgesFixedAndOriginalTargets() async throws {
        let fileURL = try makeSineFile(named: "realtime.caf", duration: 2)
        let backend = AVAudioEngineFixedEQPlaybackBackend()
        try PlaybackController.activateSystemAudioSession()
        try backend.load(url: fileURL, trackID: UUID())
        defer {
            backend.stop()
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }

        try backend.requestFixedEQAuditionMode(.fixedEQ)
        try backend.play()

        let didApplyFixedEQ = await waitUntil {
            let state = backend.fixedEQAuditionState
            return state.appliedMode == .fixedEQ
                && !state.isSwitching
                && state.failureMessage == nil
        }
        XCTAssertTrue(
            didApplyFixedEQ,
            "The realtime render graph did not acknowledge the Fixed EQ target."
        )
        let didAdvancePlayback = await waitUntil {
            backend.position > 0 && (backend.normalizedMeterLevel() ?? 0) > 0
        }
        XCTAssertTrue(
            didAdvancePlayback,
            "The player node did not advance or publish its pre-DSP meter."
        )
        XCTAssertTrue(backend.isPlaying)
        XCTAssertGreaterThan(backend.position, 0)
        XCTAssertGreaterThan(backend.normalizedMeterLevel() ?? 0, 0)

        let fixedSchedule = backend.currentSchedule
        try backend.seek(to: 0.5)
        XCTAssertNotEqual(backend.currentSchedule, fixedSchedule)
        XCTAssertEqual(backend.fixedEQAuditionState.requestedMode, .fixedEQ)

        try backend.requestFixedEQAuditionMode(.original)
        let didApplyOriginal = await waitUntil {
            let state = backend.fixedEQAuditionState
            return state.appliedMode == .original
                && !state.isSwitching
                && state.failureMessage == nil
        }
        XCTAssertTrue(
            didApplyOriginal,
            "The realtime render graph did not acknowledge the Original target."
        )
    }

    func testNewTrackAlwaysStartsInOriginal() async throws {
        let firstURL = try makeSineFile(named: "first.caf", duration: 1)
        let secondURL = try makeSineFile(named: "second.caf", duration: 1, frequency: 880)
        let backend = AVAudioEngineFixedEQPlaybackBackend()
        try PlaybackController.activateSystemAudioSession()
        try backend.load(url: firstURL, trackID: UUID())
        defer {
            backend.stop()
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
        try backend.play()
        try backend.requestFixedEQAuditionMode(.fixedEQ)
        let didApplyFixedEQ = await waitUntil {
            backend.fixedEQAuditionState.appliedMode == .fixedEQ
        }
        XCTAssertTrue(didApplyFixedEQ)

        backend.pause()
        let secondTrackID = UUID()
        try backend.load(url: secondURL, trackID: secondTrackID)

        XCTAssertEqual(backend.currentSchedule?.trackID, secondTrackID)
        XCTAssertEqual(backend.fixedEQAuditionState.requestedMode, .original)
        XCTAssertEqual(backend.fixedEQAuditionState.appliedMode, .original)
        XCTAssertFalse(backend.fixedEQAuditionState.appliesOnNextPlay)
    }

    func testSafetyResetPreservesScheduleAndReturnsToOriginalForPlayingAndPausedRoutes() async throws {
        let fileURL = try makeSineFile(named: "route-reset.caf", duration: 3)
        let backend = AVAudioEngineFixedEQPlaybackBackend()
        try PlaybackController.activateSystemAudioSession()
        try backend.load(url: fileURL, trackID: UUID())
        defer {
            backend.stop()
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
        try backend.play()
        try backend.requestFixedEQAuditionMode(.fixedEQ)
        let didApplyFixedEQWhilePlaying = await waitUntil {
            backend.fixedEQAuditionState.appliedMode == .fixedEQ
        }
        XCTAssertTrue(didApplyFixedEQWhilePlaying)

        let committedSchedule = backend.currentSchedule
        try backend.resetFixedEQAudition()

        XCTAssertEqual(backend.currentSchedule, committedSchedule)
        XCTAssertTrue(backend.isPlaying)
        XCTAssertEqual(backend.fixedEQAuditionState.requestedMode, .original)
        let didApplyOriginalWhilePlaying = await waitUntil {
            let state = backend.fixedEQAuditionState
            return state.appliedMode == .original && !state.isSwitching
        }
        XCTAssertTrue(didApplyOriginalWhilePlaying)

        try backend.requestFixedEQAuditionMode(.fixedEQ)
        let didApplyFixedEQBeforePause = await waitUntil {
            backend.fixedEQAuditionState.appliedMode == .fixedEQ
        }
        XCTAssertTrue(didApplyFixedEQBeforePause)
        backend.pause()
        let pausedPosition = backend.position

        try backend.resetFixedEQAudition()

        XCTAssertFalse(backend.isPlaying)
        XCTAssertEqual(backend.position, pausedPosition, accuracy: 1 / 48_000)
        XCTAssertEqual(backend.fixedEQAuditionState.requestedMode, .original)
        XCTAssertEqual(backend.fixedEQAuditionState.appliedMode, .fixedEQ)
        XCTAssertTrue(backend.fixedEQAuditionState.appliesOnNextPlay)

        try backend.play()
        let didApplyOriginalAfterResume = await waitUntil {
            let state = backend.fixedEQAuditionState
            return state.appliedMode == .original && !state.isSwitching
        }
        XCTAssertTrue(didApplyOriginalAfterResume)
        let didResumePlayback = await waitUntil { backend.position > pausedPosition }
        XCTAssertTrue(didResumePlayback)
    }

    private func makeSineFile(
        named name: String,
        duration: TimeInterval,
        frequency: Double = 440
    ) throws -> URL {
        let sampleRate = 48_000.0
        let channelCount = 2
        let frameCount = Int(sampleRate * duration)
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount)
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for frame in 0..<frameCount {
            let sample = Float(sin(2 * .pi * frequency * Double(frame) / sampleRate) * 0.3)
            buffer.floatChannelData![0][frame] = sample
            buffer.floatChannelData![1][frame] = -sample
        }

        let url = temporaryDirectory.appending(path: name, directoryHint: .notDirectory)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
