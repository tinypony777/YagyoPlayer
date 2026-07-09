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

    private func makeStore(with tracks: [AudioTrack], playlists: [Playlist] = []) throws -> AudioLibraryStore {
        let libraryDirectory = temporaryDirectory.appending(path: "YagyoLibrary", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(tracks).write(to: libraryDirectory.appending(path: "library.json"))
        if !playlists.isEmpty {
            try encoder.encode(playlists).write(to: libraryDirectory.appending(path: "playlists.json"))
        }

        let store = makeStore()
        store.load()
        return store
    }

    private func makeStoredTracks(count: Int, duration: TimeInterval = 12) -> [AudioTrack] {
        let importedAt = Date(timeIntervalSince1970: 1_800_000_000)
        return (0..<count).map { index in
            AudioTrack(
                title: "Track \(index + 1)",
                originalFilename: "track-\(index + 1).wav",
                storedFilename: "track-\(index + 1).wav",
                importedAt: importedAt.addingTimeInterval(TimeInterval(-index)),
                duration: duration
            )
        }
    }

    private func makeFakePlayer(
        backend: FakeAudioPlaybackBackend = FakeAudioPlaybackBackend(),
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> PlaybackController {
        PlaybackController(
            backend: backend,
            notificationCenter: notificationCenter,
            activateAudioSession: {}
        )
    }

    /// 実際にデコード・再生できる無音WAVを取り込み、本物の AVAudioPlayer ロード経路を通す。
    private func importPlayableTrack(named name: String = "clip.wav", into store: AudioLibraryStore) async throws -> AudioTrack {
        let url = temporaryDirectory.appending(path: name, directoryHint: .notDirectory)
        try Self.makeSilentWAVData().write(to: url)
        await store.importAudioFiles(from: [url])
        return try XCTUnwrap(store.tracks.first)
    }

    /// NotificationCenter の投稿から生まれる `Task { @MainActor in ... }` の実行を待つ。
    private func flushMainActor() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }

    private func nowPlayingDouble(_ key: String) -> Double? {
        let value = MPNowPlayingInfoCenter.default().nowPlayingInfo?[key]
        if let double = value as? Double {
            return double
        }
        return (value as? NSNumber)?.doubleValue
    }

    // MARK: - Backend seam characterization

    func testLoadWithoutAutoplaySelectsTrackAndPublishesBackendDuration() throws {
        let tracks = makeStoredTracks(count: 1, duration: 31)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 42)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store, autoplay: false)

        XCTAssertEqual(backend.loadCalls.map(\.trackID), [tracks[0].id])
        XCTAssertEqual(backend.playCallCount, 0)
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(player.duration, 42)
        XCTAssertEqual(player.elapsedTime, 0)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(store.selectedTrackID, tracks[0].id)
        XCTAssertNil(player.playbackErrorMessage)
    }

    func testAutoplayDelegatesPlayAndStartsTimers() throws {
        let tracks = makeStoredTracks(count: 1)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store, autoplay: true)
        backend.position = 3
        player.pollPlaybackState()

        XCTAssertEqual(backend.playCallCount, 1)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.elapsedTime, 3)
        XCTAssertNil(player.playbackErrorMessage)
    }

    func testPlayPauseVolumeAndClampedSeekDelegateToBackend() throws {
        let tracks = makeStoredTracks(count: 1)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let player = makeFakePlayer(backend: backend)
        player.load(tracks[0], from: store)

        player.volume = 0.5
        player.play()
        player.pause()
        player.seek(to: -3)
        player.seek(to: 99)

        XCTAssertEqual(backend.volume, 0.5)
        XCTAssertEqual(backend.playCallCount, 1)
        XCTAssertEqual(backend.pauseCallCount, 2, "load without autoplay pauses the backend once, then explicit pause delegates again")
        XCTAssertEqual(backend.seekCalls, [0, 10])
        XCTAssertFalse(player.isPlaying)
    }

    func testNextAndPreviousWrapWithinLibraryQueue() throws {
        let tracks = makeStoredTracks(count: 3)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store)
        player.playPrevious()
        XCTAssertEqual(player.currentTrack?.id, tracks[2].id)

        player.playNext()
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)

        player.playNext()
        XCTAssertEqual(player.currentTrack?.id, tracks[1].id)
        XCTAssertEqual(backend.loadCalls.map(\.trackID), [tracks[0].id, tracks[2].id, tracks[0].id, tracks[1].id])
        XCTAssertEqual(backend.playCallCount, 3)
    }

    func testNextUsesActivePlaylistQueue() throws {
        let tracks = makeStoredTracks(count: 3)
        let playlist = Playlist(name: "Selected", trackIDs: [tracks[0].id, tracks[2].id])
        let store = try makeStore(with: tracks, playlists: [playlist])
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store, autoplay: false, context: .playlist(playlist.id))
        player.playNext()
        XCTAssertEqual(player.currentTrack?.id, tracks[2].id)

        player.playNext()
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(store.activePlaylistID, playlist.id)
    }

    func testHalfPlayedRecordsStatisticsOnlyOncePerLoad() throws {
        let tracks = makeStoredTracks(count: 1, duration: 10)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store, autoplay: true)
        backend.position = 4.9
        player.pollPlaybackState()
        XCTAssertNil(store.tracks[0].playCount)

        backend.position = 5
        player.pollPlaybackState()
        XCTAssertEqual(store.tracks[0].playCount, 1)

        backend.position = 8
        player.pollPlaybackState()
        XCTAssertEqual(store.tracks[0].playCount, 1)
    }

    func testMatchingFinishRecordsOnceAndAdvancesQueue() throws {
        let tracks = makeStoredTracks(count: 2, duration: 10)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store, autoplay: true)
        let identity = try XCTUnwrap(backend.currentSchedule)
        backend.emit(.finished(identity))

        XCTAssertEqual(store.tracks.first { $0.id == tracks[0].id }?.playCount, 1)
        XCTAssertEqual(player.currentTrack?.id, tracks[1].id)
        XCTAssertEqual(backend.loadCalls.map(\.trackID), [tracks[0].id, tracks[1].id])
    }

    func testStaleFinishAfterSeekDoesNotAdvanceQueue() throws {
        let tracks = makeStoredTracks(count: 2, duration: 10)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store, autoplay: true)
        let staleIdentity = try XCTUnwrap(backend.currentSchedule)
        player.seek(to: 3)
        backend.emit(.finished(staleIdentity))

        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        XCTAssertNil(store.tracks.first { $0.id == tracks[0].id }?.playCount)
    }

    func testStaleFinishAfterLoadDoesNotAdvanceQueue() throws {
        let tracks = makeStoredTracks(count: 2, duration: 10)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store, autoplay: true)
        let staleIdentity = try XCTUnwrap(backend.currentSchedule)
        player.load(tracks[1], from: store, autoplay: false)
        backend.emit(.finished(staleIdentity))

        XCTAssertEqual(player.currentTrack?.id, tracks[1].id)
        XCTAssertNil(store.tracks.first { $0.id == tracks[0].id }?.playCount)
    }

    func testStaleFinishAfterStopOrDeletionDoesNotAdvanceQueue() throws {
        let tracks = makeStoredTracks(count: 2, duration: 10)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store, autoplay: true)
        let staleIdentity = try XCTUnwrap(backend.currentSchedule)
        player.stopForDeletedTrack(tracks[0])
        backend.emit(.finished(staleIdentity))

        XCTAssertNil(player.currentTrack)
        XCTAssertNil(store.tracks.first { $0.id == tracks[0].id }?.playCount)
        XCTAssertEqual(backend.stopCallCount, 1)
    }

    func testStopForDeletedTrackClearsBackendAndPublishedState() throws {
        let tracks = makeStoredTracks(count: 1, duration: 10)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store, autoplay: true)
        backend.position = 4
        player.pollPlaybackState()
        player.stopForDeletedTrack(tracks[0])

        XCTAssertEqual(backend.stopCallCount, 1)
        XCTAssertNil(backend.currentSchedule)
        XCTAssertNil(player.currentTrack)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.elapsedTime, 0)
        XCTAssertEqual(player.duration, 0)
        XCTAssertEqual(player.audioLevel, 0)
        XCTAssertNil(player.playbackErrorMessage)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }

    func testNowPlayingMirrorsElapsedDurationAndPlaybackRate() throws {
        let tracks = makeStoredTracks(count: 1, duration: 10)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 12)
        let player = makeFakePlayer(backend: backend)

        player.load(tracks[0], from: store, autoplay: true)
        backend.position = 3.5
        player.pollPlaybackState()

        XCTAssertEqual(nowPlayingDouble(MPMediaItemPropertyPlaybackDuration), 12)
        XCTAssertEqual(nowPlayingDouble(MPNowPlayingInfoPropertyElapsedPlaybackTime), 3.5)
        XCTAssertEqual(nowPlayingDouble(MPNowPlayingInfoPropertyPlaybackRate), 1)

        player.pause()
        XCTAssertEqual(nowPlayingDouble(MPNowPlayingInfoPropertyPlaybackRate), 0)
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

    // MARK: - 割り込み(電話・Siri)からの復帰は、中断前に再生中だった場合のみ

    func testInterruptionResumesOnlyIfPlaybackWasActive() async throws {
        let tracks = makeStoredTracks(count: 1)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let center = NotificationCenter()
        let player = makeFakePlayer(backend: backend, notificationCenter: center)

        player.load(tracks[0], from: store, autoplay: true)
        XCTAssertTrue(player.isPlaying)

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)]
        )
        await flushMainActor()
        XCTAssertFalse(player.isPlaying, "Playback should pause when an interruption begins")

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
                AVAudioSessionInterruptionOptionKey: NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
            ]
        )
        await flushMainActor()
        XCTAssertTrue(player.isPlaying, "Playback that was active before the interruption should resume")
        XCTAssertEqual(backend.prepareToResumeAfterInterruptionCallCount, 1)
    }

    func testInterruptionDoesNotResumePlaybackThatWasAlreadyPaused() async throws {
        let tracks = makeStoredTracks(count: 1)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let center = NotificationCenter()
        let player = makeFakePlayer(backend: backend, notificationCenter: center)

        player.load(tracks[0], from: store, autoplay: false)
        XCTAssertFalse(player.isPlaying)

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)]
        )
        await flushMainActor()

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
                AVAudioSessionInterruptionOptionKey: NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertFalse(player.isPlaying, "A track that was paused before the interruption must not auto-resume")
        XCTAssertEqual(backend.prepareToResumeAfterInterruptionCallCount, 0)
    }

    /// 通話中にさらに割り込みが重なっても、一番外側の割り込みが終わるまでは再開せず、
    /// 最終的に元の再生状態を正しく復元できることを確認する。
    func testNestedInterruptionsResumeOnlyAfterOutermostEnds() async throws {
        let tracks = makeStoredTracks(count: 1)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let center = NotificationCenter()
        let player = makeFakePlayer(backend: backend, notificationCenter: center)

        player.load(tracks[0], from: store, autoplay: true)
        XCTAssertTrue(player.isPlaying)

        func postInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) {
            var userInfo: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: NSNumber(value: type.rawValue)]
            if type == .ended {
                let options: AVAudioSession.InterruptionOptions = shouldResume ? .shouldResume : []
                userInfo[AVAudioSessionInterruptionOptionKey] = NSNumber(value: options.rawValue)
            }
            center.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: userInfo)
        }

        postInterruption(.began) // outer
        await flushMainActor()
        XCTAssertFalse(player.isPlaying)

        postInterruption(.began) // nested
        await flushMainActor()
        XCTAssertFalse(player.isPlaying)

        postInterruption(.ended, shouldResume: true) // nested ends - must NOT resume yet
        await flushMainActor()
        XCTAssertFalse(player.isPlaying, "Playback must stay paused while the outer interruption is still active")

        postInterruption(.ended, shouldResume: true) // outer ends - now it may resume
        await flushMainActor()
        XCTAssertTrue(player.isPlaying, "Playback should resume once every nested interruption has ended")
        XCTAssertEqual(backend.prepareToResumeAfterInterruptionCallCount, 1)
    }

    /// 割り込み中にイヤホンが抜けた場合、通話が終わってもスピーカーへ自動再開してはならない。
    func testRouteChangeDuringInterruptionPreventsAutoResumeToSpeaker() async throws {
        let tracks = makeStoredTracks(count: 1)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let center = NotificationCenter()
        let player = makeFakePlayer(backend: backend, notificationCenter: center)

        player.load(tracks[0], from: store, autoplay: true)
        XCTAssertTrue(player.isPlaying)

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)]
        )
        await flushMainActor()

        await backend.suspendInterruptionPreparation()
        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue),
                AVAudioSessionInterruptionOptionKey: NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
            ]
        )
        await flushMainActor()

        center.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
            ]
        )
        backend.finishInterruptionPreparation()
        await flushMainActor()

        XCTAssertFalse(player.isPlaying, "Losing the output device during interruption recovery must prevent auto-resume to the speaker")
    }

    // MARK: - ルート変更(イヤホン・AirPods抜去)は一時停止のみ。スピーカーで自動継続しない

    func testRouteChangeOldDeviceUnavailablePausesPlayback() async throws {
        let tracks = makeStoredTracks(count: 1)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let center = NotificationCenter()
        let player = makeFakePlayer(backend: backend, notificationCenter: center)

        player.load(tracks[0], from: store, autoplay: true)
        XCTAssertTrue(player.isPlaying)

        center.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertFalse(player.isPlaying, "Playback should pause when headphones/AirPods are disconnected")
        XCTAssertEqual(backend.pauseCallCount, 1)
    }

    func testRouteChangeNewDeviceAvailableDoesNotPausePlayback() async throws {
        let tracks = makeStoredTracks(count: 1)
        let store = try makeStore(with: tracks)
        let backend = FakeAudioPlaybackBackend(duration: 10)
        let center = NotificationCenter()
        let player = makeFakePlayer(backend: backend, notificationCenter: center)

        player.load(tracks[0], from: store, autoplay: true)
        XCTAssertTrue(player.isPlaying)

        center.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue)
            ]
        )
        await flushMainActor()

        XCTAssertTrue(player.isPlaying, "Only oldDeviceUnavailable should pause playback")
        XCTAssertEqual(backend.pauseCallCount, 0)
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
