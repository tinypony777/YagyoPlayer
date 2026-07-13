import AVFoundation
import MediaPlayer
import XCTest

@testable import YagyoPlayer

@MainActor
final class PlaybackBackendSeamTests: XCTestCase {
    private enum StubError: LocalizedError {
        case load
        case play

        var errorDescription: String? {
            switch self {
            case .load: "stub load failure"
            case .play: "stub play failure"
            }
        }
    }

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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testBackendReceivesLoadPlaybackSeekAndSeparatedEffectiveVolume() {
        let backend = FakeAudioPlaybackBackend(duration: 120)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let track = makeTrack(named: "subject.wav")

        controller.volume = 0.8
        controller.load(track, from: store, autoplay: true, context: .library)

        XCTAssertEqual(backend.loadCalls.count, 1)
        XCTAssertEqual(backend.loadCalls.first?.trackID, track.id)
        XCTAssertEqual(backend.loadCalls.first?.url, store.fileURL(for: track))
        XCTAssertEqual(backend.playCallCount, 1)
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.duration, 120)
        XCTAssertEqual(backend.outputVolume, 0.8, accuracy: 1e-6)

        controller.setLoudnessMatchMultiplier(0.5)
        XCTAssertEqual(controller.volume, 0.8, accuracy: 1e-6)
        XCTAssertEqual(backend.outputVolume, 0.4, accuracy: 1e-6)

        controller.seek(to: 999)
        XCTAssertEqual(backend.seekCalls.last, 120)
        controller.elapsedTime = 0
        XCTAssertEqual(controller.currentPlaybackTime, 120)

        controller.clearLoudnessMatch()
        XCTAssertEqual(backend.outputVolume, 0.8, accuracy: 1e-6)
        controller.pause()
        XCTAssertFalse(controller.isPlaying)
    }

    func testFailedReplacementLoadKeepsOldTrackPausedAndClearsMatch() {
        let backend = FakeAudioPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let oldTrack = makeTrack(named: "old.wav")
        let replacement = makeTrack(named: "replacement.wav")

        controller.load(oldTrack, from: store, autoplay: true)
        controller.volume = 0.75
        controller.setLoudnessMatchMultiplier(0.5)
        backend.loadError = StubError.load

        controller.load(replacement, from: store, autoplay: true)

        XCTAssertEqual(controller.currentTrack?.id, oldTrack.id)
        XCTAssertEqual(backend.currentSchedule?.trackID, oldTrack.id)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(backend.isPlaying)
        XCTAssertFalse(controller.isLoudnessMatchActive)
        XCTAssertEqual(controller.loudnessMatchMultiplier, 1, accuracy: 1e-6)
        XCTAssertEqual(backend.outputVolume, 0.75, accuracy: 1e-6)
        XCTAssertTrue(controller.playbackErrorMessage?.contains(replacement.title) == true)
    }

    func testPartiallyMutatedFailedLoadCannotLeaveStaleTrackControllingBackend() {
        let backend = FakeAudioPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let oldTrack = makeTrack(named: "old.wav")
        let replacement = makeTrack(named: "partial-replacement.wav")

        controller.load(oldTrack, from: store, autoplay: true)
        backend.loadErrorAfterMutation = StubError.load

        controller.load(replacement, from: store, autoplay: true)

        XCTAssertNil(controller.currentTrack)
        XCTAssertNil(backend.currentSchedule)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(backend.isPlaying)
        XCTAssertEqual(controller.elapsedTime, 0)
        XCTAssertEqual(controller.duration, 0)
        XCTAssertEqual(backend.stopCallCount, 1)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertTrue(controller.playbackErrorMessage?.contains(replacement.title) == true)

        controller.play()
        controller.seek(to: 10)

        XCTAssertEqual(backend.playCallCount, 1)
        XCTAssertTrue(backend.seekCalls.isEmpty)
    }

    func testSameTrackPartialReloadFailureCannotHideBehindMatchingTrackID() {
        let backend = FakeAudioPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let track = makeTrack(named: "same-track.wav")

        controller.load(track, from: store, autoplay: true)
        let committedSchedule = backend.currentSchedule
        backend.loadErrorAfterMutation = StubError.load

        controller.load(track, from: store, autoplay: true)

        XCTAssertNil(controller.currentTrack)
        XCTAssertNil(backend.currentSchedule)
        XCTAssertNotNil(committedSchedule)
        XCTAssertEqual(backend.stopCallCount, 1)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertTrue(controller.playbackErrorMessage?.contains(track.title) == true)
    }

    func testSuccessfulLoadWithoutNewIdentityFailsClosedAfterTransportMutation() {
        let backend = FakeAudioPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let oldTrack = makeTrack(named: "old.wav")
        let replacement = makeTrack(named: "unpublished-replacement.wav")

        controller.load(oldTrack, from: store, autoplay: true)
        let oldSchedule = backend.currentSchedule
        backend.suppressSchedulePublicationOnLoad = true

        controller.load(replacement, from: store, autoplay: true)

        XCTAssertNotNil(oldSchedule)
        XCTAssertNil(controller.currentTrack)
        XCTAssertNil(backend.currentSchedule)
        XCTAssertEqual(backend.stopCallCount, 1)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertTrue(controller.playbackErrorMessage?.contains(replacement.title) == true)
    }

    func testSuccessfulSeekWithoutNewIdentityFailsClosedAfterPositionMutation() {
        let backend = FakeAudioPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let track = makeTrack(named: "unpublished-seek.wav")

        controller.load(track, from: store, autoplay: true)
        let oldSchedule = backend.currentSchedule
        backend.suppressSchedulePublicationOnSeek = true

        controller.seek(to: 12)

        XCTAssertNotNil(oldSchedule)
        XCTAssertEqual(backend.seekCalls, [12])
        XCTAssertNil(controller.currentTrack)
        XCTAssertNil(backend.currentSchedule)
        XCTAssertEqual(backend.stopCallCount, 1)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertTrue(controller.playbackErrorMessage?.contains("did not commit") == true)
    }

    func testBackendPlayFailureUsesExistingFailClosedControllerState() {
        let backend = FakeAudioPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let track = makeTrack(named: "play-error.wav")
        controller.load(track, from: store)
        backend.playError = StubError.play

        controller.play()

        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.playbackErrorMessage, "stub play failure")
        XCTAssertEqual(controller.paradeSignals.snapshot.activity, .stopped)
        XCTAssertEqual(controller.audioLevel, 0)
    }

    func testInterruptionResumeUsesInjectedAudioSessionActivation() async {
        let backend = FakeAudioPlaybackBackend(duration: 30)
        var activationCount = 0
        let controller = PlaybackController(
            backend: backend,
            activateAudioSession: { activationCount += 1 }
        )
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        controller.load(makeTrack(named: "interruption.wav"), from: store, autoplay: true)
        XCTAssertEqual(activationCount, 1)

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey:
                    NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)
            ]
        )
        await flushMainActor()
        XCTAssertFalse(controller.isPlaying)

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey:
                    NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
                AVAudioSessionInterruptionOptionKey:
                    NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(activationCount, 2)
        controller.pause()
    }

    func testFixedEQAuditionStaysSeparateFromTobariLoudnessMatch() {
        let backend = FakeFixedEQAuditionPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let track = makeTrack(named: "same-track-preview.wav")

        XCTAssertTrue(controller.supportsFixedEQAudition)
        XCTAssertEqual(controller.fixedEQAuditionState, .waitingForTrack)

        controller.load(track, from: store, autoplay: true)
        controller.setLoudnessMatchMultiplier(0.5)
        controller.selectFixedEQAuditionMode(.fixedEQ)

        XCTAssertEqual(backend.requestedModes, [.fixedEQ])
        XCTAssertEqual(controller.fixedEQAuditionState.requestedMode, .fixedEQ)
        XCTAssertEqual(controller.fixedEQAuditionState.appliedMode, .fixedEQ)
        XCTAssertTrue(controller.isLoudnessMatchActive)
        XCTAssertEqual(controller.loudnessMatchMultiplier, 0.5, accuracy: 1e-6)
        XCTAssertNil(controller.fixedEQAuditionMessage)
        controller.pause()
    }

    func testRouteLossReturnsFixedEQAuditionToOriginal() async {
        let backend = FakeFixedEQAuditionPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let track = makeTrack(named: "headphones.wav")

        controller.load(track, from: store, autoplay: true)
        controller.selectFixedEQAuditionMode(.fixedEQ)
        let resetsBeforeRouteLoss = backend.resetCallCount

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    NSNumber(value: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(backend.resetCallCount, resetsBeforeRouteLoss + 1)
        XCTAssertEqual(controller.fixedEQAuditionState.requestedMode, .original)
        XCTAssertEqual(controller.fixedEQAuditionState.appliedMode, .original)
    }

    func testBluetoothProfileRouteChangeKeepsPlaybackButReturnsToOriginal() async {
        let backend = FakeFixedEQAuditionPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let track = makeTrack(named: "bluetooth-profile.wav")

        controller.load(track, from: store, autoplay: true)
        controller.selectFixedEQAuditionMode(.fixedEQ)
        let resetsBeforeRouteChange = backend.resetCallCount

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    NSNumber(value: AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(backend.resetCallCount, resetsBeforeRouteChange + 1)
        XCTAssertEqual(controller.fixedEQAuditionState.requestedMode, .original)
        XCTAssertEqual(controller.fixedEQAuditionState.appliedMode, .original)
    }

    func testRouteResetFailurePausesInsteadOfLeavingFixedEQAudible() async {
        let backend = FakeFixedEQAuditionPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let track = makeTrack(named: "route-reset-failure.wav")

        controller.load(track, from: store, autoplay: true)
        controller.selectFixedEQAuditionMode(.fixedEQ)
        backend.auditionError = StubError.play

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    NSNumber(value: AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(backend.isPlaying)
        XCTAssertNotNil(controller.fixedEQAuditionMessage)
        XCTAssertEqual(controller.fixedEQAuditionState.appliedMode, .fixedEQ)

        backend.auditionError = nil
        controller.play()

        XCTAssertTrue(controller.isPlaying)
        XCTAssertNil(controller.fixedEQAuditionMessage)
    }

    func testSuccessfulLoadClearsAuditionErrorFromReplacedGraph() async {
        let backend = FakeFixedEQAuditionPlaybackBackend(duration: 30)
        let controller = makeController(backend: backend)
        let store = AudioLibraryStore(documentsDirectory: temporaryDirectory)
        let firstTrack = makeTrack(named: "failed-reset-source.wav")
        let secondTrack = makeTrack(named: "fresh-original.wav")

        controller.load(firstTrack, from: store, autoplay: true)
        controller.selectFixedEQAuditionMode(.fixedEQ)
        backend.auditionError = StubError.play

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    NSNumber(value: AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue)
            ]
        )
        await flushMainActor()
        XCTAssertNotNil(controller.fixedEQAuditionMessage)

        controller.load(secondTrack, from: store, autoplay: false)

        XCTAssertEqual(controller.currentTrack?.id, secondTrack.id)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.fixedEQAuditionState.appliedMode, .original)
        XCTAssertNil(controller.fixedEQAuditionMessage)
    }

    private func makeController(backend: FakeAudioPlaybackBackend) -> PlaybackController {
        PlaybackController(backend: backend, activateAudioSession: {})
    }

    private func makeTrack(named filename: String) -> AudioTrack {
        AudioTrack(
            title: filename,
            originalFilename: filename,
            storedFilename: filename
        )
    }

    private func flushMainActor() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}
