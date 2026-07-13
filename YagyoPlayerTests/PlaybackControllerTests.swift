import AVFoundation
import MediaPlayer
import XCTest
@testable import YagyoPlayer

@MainActor
final class PlaybackControllerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() async throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func makeStore() -> AudioLibraryStore {
        AudioLibraryStore(documentsDirectory: temporaryDirectory)
    }

    /// 実際にデコード・再生できる無音WAVを取り込み、本物の AVAudioPlayer ロード経路を通す。
    private func importPlayableTrack(
        named name: String = "clip.wav",
        sampleCount: Int = 4000,
        into store: AudioLibraryStore
    ) async throws -> AudioTrack {
        let url = temporaryDirectory.appending(path: name, directoryHint: .notDirectory)
        try Self.makeSilentWAVData(sampleCount: sampleCount).write(to: url)
        await store.importAudioFiles(from: [url])
        return try XCTUnwrap(store.tracks.first { $0.originalFilename == name })
    }

    /// NotificationCenter の投稿から生まれる `Task { @MainActor in ... }` の実行を待つ。
    private func flushMainActor() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    private func primeStrongParadeSignal(on player: PlaybackController) {
        player.paradeSignals.ingest(level: 0.20, isPlaying: true, sampledAt: 0)
        player.paradeSignals.ingest(level: 0.20, isPlaying: true, sampledAt: 0.31)
        player.paradeSignals.ingest(level: 0.80, isPlaying: true, sampledAt: 0.40)
    }

    // MARK: - 狐火の帳 Phase B は基準音量と減衰乗数を分離する

    func testLoudnessMatchMultiplierDoesNotOverwriteBaseVolume() {
        let player = PlaybackController()
        player.volume = 0.8

        player.setLoudnessMatchMultiplier(0.5)

        XCTAssertEqual(player.volume, 0.8, accuracy: 1e-6)
        XCTAssertEqual(player.loudnessMatchMultiplier, 0.5, accuracy: 1e-6)
        XCTAssertTrue(player.isLoudnessMatchActive)
        XCTAssertEqual(player.effectiveVolume, 0.4, accuracy: 1e-6)

        player.clearLoudnessMatch()

        XCTAssertEqual(player.volume, 0.8, accuracy: 1e-6)
        XCTAssertEqual(player.loudnessMatchMultiplier, 1, accuracy: 1e-6)
        XCTAssertFalse(player.isLoudnessMatchActive)
        XCTAssertEqual(player.effectiveVolume, 0.8, accuracy: 1e-6)
    }

    func testLoudnessMatchMultiplierCannotBoostOrPropagateNonFiniteValues() {
        let player = PlaybackController()
        player.volume = 0.75

        player.setLoudnessMatchMultiplier(1.4)
        XCTAssertEqual(player.loudnessMatchMultiplier, 1, accuracy: 1e-6)
        XCTAssertTrue(player.isLoudnessMatchActive, "0 dB側も比較セッションとしては適用中")
        XCTAssertEqual(player.effectiveVolume, 0.75, accuracy: 1e-6)

        player.setLoudnessMatchMultiplier(.nan)
        XCTAssertEqual(player.loudnessMatchMultiplier, 1, accuracy: 1e-6)
        XCTAssertFalse(player.isLoudnessMatchActive)

        player.setLoudnessMatchMultiplier(-0.4)
        XCTAssertEqual(player.loudnessMatchMultiplier, 0, accuracy: 1e-6)
        XCTAssertEqual(player.effectiveVolume, 0, accuracy: 1e-6)
    }

    func testLoadingAnotherTrackClearsLoudnessMatchWithoutChangingBaseVolume() async throws {
        let store = makeStore()
        store.load()
        let firstTrack = try await importPlayableTrack(named: "first.wav", into: store)
        let nextTrack = try await importPlayableTrack(named: "next.wav", sampleCount: 4001, into: store)
        let player = PlaybackController()
        player.volume = 0.72
        player.load(firstTrack, from: store)
        player.play()
        XCTAssertTrue(player.isPlaying)
        player.setLoudnessMatchMultiplier(0.4)

        player.load(nextTrack, from: store)

        XCTAssertEqual(player.currentTrack?.id, nextTrack.id)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.volume, 0.72, accuracy: 1e-6)
        XCTAssertEqual(player.loudnessMatchMultiplier, 1, accuracy: 1e-6)
        XCTAssertFalse(player.isLoudnessMatchActive)
        XCTAssertEqual(player.effectiveVolume, 0.72, accuracy: 1e-6)
    }

    func testReloadingSameTrackClearsMatchSessionEvenWhenTrackIDDoesNotChange() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)
        let player = PlaybackController()
        player.load(track, from: store)
        player.play()
        XCTAssertTrue(player.isPlaying)
        player.setLoudnessMatchMultiplier(0.4)

        player.load(track, from: store)

        XCTAssertEqual(player.currentTrack?.id, track.id)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.loudnessMatchMultiplier, 1, accuracy: 1e-6)
        XCTAssertFalse(player.isLoudnessMatchActive)
    }

    func testFailedTrackLoadClearsMatchSessionFromPreviouslyLoadedTrack() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)
        let player = PlaybackController()
        player.load(track, from: store)
        player.play()
        XCTAssertTrue(player.isPlaying)
        player.setLoudnessMatchMultiplier(0.4)
        let missing = AudioTrack(
            title: "参照なし",
            originalFilename: "missing.wav",
            storedFilename: "missing-\(UUID().uuidString).wav"
        )

        player.load(missing, from: store)

        XCTAssertEqual(player.currentTrack?.id, track.id)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.loudnessMatchMultiplier, 1, accuracy: 1e-6)
        XCTAssertFalse(player.isLoudnessMatchActive)
        XCTAssertNotNil(player.playbackErrorMessage)
    }

    func testCurrentPlaybackTimeReadsBackendInsteadOfStalePublishedTick() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)
        let player = PlaybackController()
        player.load(track, from: store)
        player.seek(to: 0.3)
        player.elapsedTime = 0

        XCTAssertEqual(player.currentPlaybackTime, 0.3, accuracy: 0.01)
    }

    func testLibraryContextClearsStalePlaylistBeforeComparisonReferenceLoad() async throws {
        let store = makeStore()
        store.load()
        let libraryNext = try await importPlayableTrack(
            named: "library-next.wav",
            sampleCount: 4002,
            into: store
        )
        let reference = try await importPlayableTrack(
            named: "reference.wav",
            sampleCount: 4001,
            into: store
        )
        let subject = try await importPlayableTrack(named: "subject.wav", into: store)
        let playlist = try XCTUnwrap(store.createPlaylist(named: "比較前の巻物"))
        store.addTrack(subject, to: playlist)
        let player = PlaybackController()
        player.load(subject, from: store, context: .playlist(playlist.id))
        XCTAssertEqual(store.activePlaylistID, playlist.id)

        player.load(reference, from: store, context: .library)

        XCTAssertNil(store.activePlaylistID)
        XCTAssertEqual(player.currentTrack?.id, reference.id)
        XCTAssertEqual(store.nextTrack(after: reference)?.id, libraryNext.id)
    }

    func testPauseKeepsMatchForResumeButTrueStopClearsIt() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)
        let player = PlaybackController()
        player.load(track, from: store)
        player.setLoudnessMatchMultiplier(0.5)

        player.pause()
        XCTAssertTrue(player.isLoudnessMatchActive, "一時停止から同じA/B条件で再開できる")

        player.stopForDeletedTrack(track)
        XCTAssertFalse(player.isLoudnessMatchActive)
        XCTAssertEqual(player.loudnessMatchMultiplier, 1, accuracy: 1e-6)
    }

    // MARK: - ファイル欠落・読み込み失敗は無言で止まらない

    func testLoadingMissingFileSurfacesPlaybackError() async throws {
        let store = makeStore()
        store.load()
        let player = PlaybackController()

        let ghostTrack = AudioTrack(
            title: "行方知れず",
            originalFilename: "ghost.wav",
            storedFilename: "does-not-exist-\(UUID().uuidString).wav"
        )

        player.load(ghostTrack, from: store)

        XCTAssertFalse(player.isPlaying)
        let message = try XCTUnwrap(player.playbackErrorMessage)
        XCTAssertTrue(message.contains(ghostTrack.title))
    }

    func testLoadingMissingFileClearsStrongParadeSignal() {
        let store = makeStore()
        store.load()
        let player = PlaybackController()
        let ghostTrack = AudioTrack(
            title: "行方知れず",
            originalFilename: "ghost.wav",
            storedFilename: "does-not-exist-\(UUID().uuidString).wav"
        )
        primeStrongParadeSignal(on: player)
        XCTAssertNotEqual(player.paradeSignals.snapshot.strongPhase, .inactive)

        player.load(ghostTrack, from: store)

        XCTAssertEqual(player.paradeSignals.snapshot.strongPhase, .inactive)
        XCTAssertEqual(player.paradeSignals.snapshot.activity, .stopped)
        XCTAssertEqual(player.audioLevel, 0)
    }

    func testLoadingCorruptFileSurfacesPlaybackError() async throws {
        let store = makeStore()
        store.load()

        let url = temporaryDirectory.appending(path: "broken.wav", directoryHint: .notDirectory)
        try Data("not actually audio".utf8).write(to: url)
        await store.importAudioFiles(from: [url])
        let track = try XCTUnwrap(store.tracks.first)

        let player = PlaybackController()
        player.load(track, from: store)

        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.playbackErrorMessage)
    }

    func testRefreshingCurrentTrackMetadataUpdatesLoadedTrackAndNowPlayingInfo() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)

        let player = PlaybackController()
        player.load(track, from: store)

        var updatedTrack = track
        updatedTrack.title = "月下のデモ"
        updatedTrack.artist = "Ryusei"

        player.refreshCurrentTrackMetadata(updatedTrack)

        XCTAssertEqual(player.currentTrack?.title, "月下のデモ")
        XCTAssertEqual(player.currentTrack?.artist, "Ryusei")
        let nowPlayingInfo = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(nowPlayingInfo[MPMediaItemPropertyTitle] as? String, "月下のデモ")
        XCTAssertEqual(nowPlayingInfo[MPMediaItemPropertyArtist] as? String, "Ryusei")
    }

    // MARK: - 再生境界では古い強い音量上昇近似を保持しない

    func testPauseClearsStrongParadeSignal() {
        let player = PlaybackController()
        primeStrongParadeSignal(on: player)
        XCTAssertNotEqual(player.paradeSignals.snapshot.strongPhase, .inactive)

        player.pause()

        XCTAssertEqual(player.paradeSignals.snapshot.strongPhase, .inactive)
        XCTAssertEqual(player.paradeSignals.snapshot.activity, .stopped)
        XCTAssertEqual(player.audioLevel, 0)
    }

    func testSeekClearsStrongParadeSignalWithoutStoppingPlayback() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)
        let player = PlaybackController()
        player.load(track, from: store, autoplay: true)
        try XCTSkipUnless(player.isPlaying, "Audio playback is not available in this test environment")
        primeStrongParadeSignal(on: player)
        XCTAssertNotEqual(player.paradeSignals.snapshot.strongPhase, .inactive)

        player.seek(to: 0.25)

        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.paradeSignals.snapshot.strongPhase, .inactive)
        XCTAssertEqual(player.paradeSignals.snapshot.activity, .unavailable)
        XCTAssertEqual(player.audioLevel, 0)
    }

    // MARK: - 割り込み(電話・Siri)からの復帰は、中断前に再生中だった場合のみ

    func testInterruptionResumesOnlyIfPlaybackWasActive() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)

        let player = PlaybackController()
        player.load(track, from: store, autoplay: true)
        try XCTSkipUnless(player.isPlaying, "Audio playback is not available in this test environment")

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)]
        )
        await flushMainActor()
        XCTAssertFalse(player.isPlaying, "Playback should pause when an interruption begins")

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
                AVAudioSessionInterruptionOptionKey: NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
            ]
        )
        await flushMainActor()
        XCTAssertTrue(player.isPlaying, "Playback that was active before the interruption should resume")
    }

    func testInterruptionDoesNotResumePlaybackThatWasAlreadyPaused() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)

        let player = PlaybackController()
        player.load(track, from: store, autoplay: false)
        XCTAssertFalse(player.isPlaying)

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)]
        )
        await flushMainActor()

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
                AVAudioSessionInterruptionOptionKey: NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertFalse(player.isPlaying, "A track that was paused before the interruption must not auto-resume")
    }

    /// 通話中にさらに割り込みが重なっても、一番外側の割り込みが終わるまでは再開せず、
    /// 最終的に元の再生状態を正しく復元できることを確認する。
    func testNestedInterruptionsResumeOnlyAfterOutermostEnds() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)

        let player = PlaybackController()
        player.load(track, from: store, autoplay: true)
        try XCTSkipUnless(player.isPlaying, "Audio playback is not available in this test environment")

        func postInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) {
            var userInfo: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: NSNumber(value: type.rawValue)]
            if type == .ended {
                let options: AVAudioSession.InterruptionOptions = shouldResume ? .shouldResume : []
                userInfo[AVAudioSessionInterruptionOptionKey] = NSNumber(value: options.rawValue)
            }
            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: userInfo)
        }

        postInterruption(.began) // outer
        await flushMainActor()
        XCTAssertFalse(player.isPlaying)

        postInterruption(.began) // nested
        await flushMainActor()
        XCTAssertFalse(player.isPlaying)

        postInterruption(.ended, shouldResume: true) // nested ends — must NOT resume yet
        await flushMainActor()
        XCTAssertFalse(player.isPlaying, "Playback must stay paused while the outer interruption is still active")

        postInterruption(.ended, shouldResume: true) // outer ends — now it may resume
        await flushMainActor()
        XCTAssertTrue(player.isPlaying, "Playback should resume once every nested interruption has ended")
    }

    /// 割り込み中にイヤホンが抜けた場合、通話が終わってもスピーカーへ自動再開してはならない。
    func testRouteChangeDuringInterruptionPreventsAutoResumeToSpeaker() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)

        let player = PlaybackController()
        player.load(track, from: store, autoplay: true)
        try XCTSkipUnless(player.isPlaying, "Audio playback is not available in this test environment")

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)]
        )
        await flushMainActor()

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
            ]
        )
        await flushMainActor()

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
                AVAudioSessionInterruptionOptionKey: NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertFalse(player.isPlaying, "Losing the output device during an interruption must prevent auto-resume to the speaker")
    }

    // MARK: - ルート変更(イヤホン・AirPods抜去)は一時停止のみ。スピーカーで自動継続しない

    func testRouteChangeOldDeviceUnavailablePausesPlayback() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)

        let player = PlaybackController()
        player.load(track, from: store, autoplay: true)
        try XCTSkipUnless(player.isPlaying, "Audio playback is not available in this test environment")

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertFalse(player.isPlaying, "Playback should pause when headphones/AirPods are disconnected")
    }

    func testRouteChangeNewDeviceAvailableDoesNotPausePlayback() async throws {
        let store = makeStore()
        store.load()
        let track = try await importPlayableTrack(into: store)

        let player = PlaybackController()
        player.load(track, from: store, autoplay: true)
        try XCTSkipUnless(player.isPlaying, "Audio playback is not available in this test environment")

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertTrue(player.isPlaying, "Only oldDeviceUnavailable should pause playback")
    }

    /// PCM16・無音のWAVをその場で組み立てる(外部フィクスチャ不要)。
    private static func makeSilentWAVData(sampleCount: Int = 4000, sampleRate: UInt32 = 8000) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(sampleCount * Int(blockAlign))
        let chunkSize = 36 + dataSize

        var data = Data()
        func appendString(_ string: String) { data.append(contentsOf: string.utf8) }
        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        appendString("RIFF")
        appendUInt32(chunkSize)
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(numChannels)
        appendUInt32(sampleRate)
        appendUInt32(byteRate)
        appendUInt16(blockAlign)
        appendUInt16(bitsPerSample)
        appendString("data")
        appendUInt32(dataSize)
        data.append(Data(count: Int(dataSize)))

        return data
    }
}
