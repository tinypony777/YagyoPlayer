import XCTest
@testable import YagyoPlayer

@MainActor
final class AudioLibraryStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() async throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func makeStore() -> AudioLibraryStore {
        AudioLibraryStore(documentsDirectory: temporaryDirectory)
    }

    private func writeSourceFile(named name: String, contents: String) throws -> URL {
        let url = temporaryDirectory.appending(path: name, directoryHint: .notDirectory)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testImportAssignsContentHash() async throws {
        let store = makeStore()
        store.load()

        let source = try writeSourceFile(named: "demo.wav", contents: "yagyo-demo-audio")
        await store.importAudioFiles(from: [source])

        XCTAssertEqual(store.tracks.count, 1)
        let hash = try XCTUnwrap(store.tracks.first?.contentHash)
        XCTAssertEqual(hash.count, 64)
        XCTAssertEqual(store.importState, .finished(ImportSummary(imported: 1)))
    }

    func testImportSkipsDuplicateContent() async throws {
        let store = makeStore()
        store.load()

        let first = try writeSourceFile(named: "take1.wav", contents: "same-audio-bytes")
        let second = try writeSourceFile(named: "take2.wav", contents: "same-audio-bytes")
        await store.importAudioFiles(from: [first, second])

        XCTAssertEqual(store.tracks.count, 1)
        XCTAssertEqual(store.importState, .finished(ImportSummary(imported: 1, duplicates: 1)))

        // 既に取り込まれた音源をもう一度取り込もうとしても重複として弾かれる
        await store.importAudioFiles(from: [first])
        XCTAssertEqual(store.tracks.count, 1)
        XCTAssertEqual(store.importState, .finished(ImportSummary(imported: 0, duplicates: 1)))
    }

    func testImportReportsUnsupportedFilesAsFailures() async throws {
        let store = makeStore()
        store.load()

        let audio = try writeSourceFile(named: "song.wav", contents: "audio")
        let text = try writeSourceFile(named: "readme.txt", contents: "not audio")
        await store.importAudioFiles(from: [audio, text])

        XCTAssertEqual(store.tracks.count, 1)
        guard case .finished(let summary) = store.importState else {
            return XCTFail("Expected finished import state")
        }
        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.failures.count, 1)
        XCTAssertEqual(summary.failures.first?.filename, "readme.txt")
    }

    func testRecordPlaybackUpdatesStatsAndPersists() async throws {
        let store = makeStore()
        store.load()

        let source = try writeSourceFile(named: "night.wav", contents: "night-audio")
        await store.importAudioFiles(from: [source])
        let track = try XCTUnwrap(store.tracks.first)

        let playedAt = Date()
        store.recordPlayback(for: track.id, at: playedAt)
        store.recordPlayback(for: track.id, at: playedAt)

        let updated = try XCTUnwrap(store.tracks.first)
        XCTAssertEqual(updated.playCount, 2)
        XCTAssertEqual(updated.lastPlayedAt?.timeIntervalSince1970 ?? 0, playedAt.timeIntervalSince1970, accuracy: 1)
        let hourKey = String(Calendar.current.component(.hour, from: playedAt))
        XCTAssertEqual(updated.playHourCounts?[hourKey], 2)

        // 別インスタンスで読み直しても統計が生きている(永続化の確認)
        let reloaded = makeStore()
        reloaded.load()
        let persisted = try XCTUnwrap(reloaded.tracks.first)
        XCTAssertEqual(persisted.playCount, 2)
        XCTAssertEqual(persisted.playHourCounts?[hourKey], 2)
    }

    func testReimportingLegacyTrackWithoutHashIsDetectedAsDuplicate() async throws {
        // PR前に取り込まれた曲(contentHash なし)が library.json と保存済みファイルにある状態を再現
        let libraryDirectory = temporaryDirectory.appending(path: "YagyoLibrary", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        try Data("legacy-audio-bytes".utf8)
            .write(to: libraryDirectory.appending(path: "old-abc.wav", directoryHint: .notDirectory))
        let legacyJSON = """
        [
          {
            "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "title": "Old Track",
            "originalFilename": "old.wav",
            "storedFilename": "old-abc.wav",
            "importedAt": "2025-01-01T00:00:00Z",
            "duration": 120
          }
        ]
        """
        try Data(legacyJSON.utf8)
            .write(to: libraryDirectory.appending(path: "library.json", directoryHint: .notDirectory))

        let store = makeStore()
        store.load()
        XCTAssertNil(store.tracks.first?.contentHash)

        // 同じ内容の音源を再取込しても、バックフィルしたハッシュにより重複として弾かれる
        let source = try writeSourceFile(named: "old.wav", contents: "legacy-audio-bytes")
        await store.importAudioFiles(from: [source])

        XCTAssertEqual(store.tracks.count, 1)
        XCTAssertEqual(store.importState, .finished(ImportSummary(imported: 0, duplicates: 1)))
        XCTAssertEqual(store.tracks.first?.contentHash?.count, 64)

        // バックフィルしたハッシュが永続化されている
        let reloaded = makeStore()
        reloaded.load()
        XCTAssertEqual(reloaded.tracks.first?.contentHash?.count, 64)
    }

    func testImportDoesNotReportSuccessWhenSaveFails() async throws {
        let store = makeStore()
        store.load()

        // library.json のパスを中身のあるディレクトリにして保存を失敗させる
        let manifestURL = temporaryDirectory
            .appending(path: "YagyoLibrary", directoryHint: .isDirectory)
            .appending(path: "library.json", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: true)
        try Data("block".utf8).write(to: manifestURL.appending(path: "blocker", directoryHint: .notDirectory))

        let source = try writeSourceFile(named: "song.wav", contents: "audio-bytes")
        await store.importAudioFiles(from: [source])

        XCTAssertTrue(store.tracks.isEmpty)
        guard case .finished(let summary) = store.importState else {
            return XCTFail("Expected finished import state")
        }
        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.duplicates, 0)
        XCTAssertEqual(summary.failures.count, 1)
        XCTAssertEqual(summary.failures.first?.filename, "song.wav")
    }

    func testRecordPlaybackSurfacesSaveFailure() async throws {
        let store = makeStore()
        store.load()

        let source = try writeSourceFile(named: "song.wav", contents: "audio-bytes")
        await store.importAudioFiles(from: [source])
        let track = try XCTUnwrap(store.tracks.first)

        // 取込後に library.json を書き込めない状態にする
        let manifestURL = temporaryDirectory
            .appending(path: "YagyoLibrary", directoryHint: .isDirectory)
            .appending(path: "library.json", directoryHint: .notDirectory)
        try FileManager.default.removeItem(at: manifestURL)
        let blockedManifest = temporaryDirectory
            .appending(path: "YagyoLibrary", directoryHint: .isDirectory)
            .appending(path: "library.json", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: blockedManifest, withIntermediateDirectories: true)
        try Data("block".utf8).write(to: blockedManifest.appending(path: "blocker", directoryHint: .notDirectory))

        store.recordPlayback(for: track.id)

        XCTAssertNotNil(store.persistenceErrorMessage)
        XCTAssertEqual(store.tracks.first?.playCount, 1)
    }

    func testDeleteRemovesTrackAndFile() async throws {
        let store = makeStore()
        store.load()

        let source = try writeSourceFile(named: "gone.wav", contents: "vanish")
        await store.importAudioFiles(from: [source])
        let track = try XCTUnwrap(store.tracks.first)
        let fileURL = store.fileURL(for: track)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.delete(track)

        XCTAssertTrue(store.tracks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(store.persistenceErrorMessage)

        // 別インスタンスで読み直しても削除が永続化されている
        let reloaded = makeStore()
        reloaded.load()
        XCTAssertTrue(reloaded.tracks.isEmpty)
    }

    func testDeleteRollsBackAndKeepsFileWhenSaveFails() async throws {
        let store = makeStore()
        store.load()

        let source = try writeSourceFile(named: "keepme.wav", contents: "keep-audio-bytes")
        await store.importAudioFiles(from: [source])
        let track = try XCTUnwrap(store.tracks.first)
        let fileURL = store.fileURL(for: track)

        // 削除実行前に library.json を書き込めない状態にする
        let manifestURL = temporaryDirectory
            .appending(path: "YagyoLibrary", directoryHint: .isDirectory)
            .appending(path: "library.json", directoryHint: .notDirectory)
        try FileManager.default.removeItem(at: manifestURL)
        let blockedManifest = temporaryDirectory
            .appending(path: "YagyoLibrary", directoryHint: .isDirectory)
            .appending(path: "library.json", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: blockedManifest, withIntermediateDirectories: true)
        try Data("block".utf8).write(to: blockedManifest.appending(path: "blocker", directoryHint: .notDirectory))

        store.delete(track)

        XCTAssertEqual(store.tracks.count, 1, "A failed save must roll back the in-memory deletion")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.path),
            "The audio file must not be removed when the manifest save fails"
        )
        XCTAssertNotNil(store.persistenceErrorMessage)
    }

    func testDeleteRollsBackPlaylistMembershipWhenSaveFails() async throws {
        let store = makeStore()
        store.load()

        let source = try writeSourceFile(named: "inplaylist.wav", contents: "playlist-audio-bytes")
        await store.importAudioFiles(from: [source])
        let track = try XCTUnwrap(store.tracks.first)

        let playlist = try XCTUnwrap(store.createPlaylist(named: "夜の巻物"))
        store.addTrack(track, to: playlist)
        XCTAssertTrue(store.playlists.first?.contains(track.id) ?? false)

        // 削除実行前に library.json を書き込めない状態にする
        let manifestURL = temporaryDirectory
            .appending(path: "YagyoLibrary", directoryHint: .isDirectory)
            .appending(path: "library.json", directoryHint: .notDirectory)
        try FileManager.default.removeItem(at: manifestURL)
        let blockedManifest = temporaryDirectory
            .appending(path: "YagyoLibrary", directoryHint: .isDirectory)
            .appending(path: "library.json", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: blockedManifest, withIntermediateDirectories: true)
        try Data("block".utf8).write(to: blockedManifest.appending(path: "blocker", directoryHint: .notDirectory))

        store.delete(track)

        XCTAssertEqual(store.tracks.count, 1, "A failed save must roll back the in-memory deletion")
        XCTAssertTrue(
            store.playlists.first?.contains(track.id) ?? false,
            "Playlist membership must also roll back when the manifest save fails, not just tracks"
        )
        XCTAssertNotNil(store.persistenceErrorMessage)

        // playlists.json はまだ書き換えていないはずなので、永続化済みの所属が残っている。
        // このテストでは library.json 自体を壊しているため、store.load() ではなく
        // playlists.json を直接確認する。
        let playlistsURL = temporaryDirectory
            .appending(path: "YagyoLibrary", directoryHint: .isDirectory)
            .appending(path: "playlists.json", directoryHint: .notDirectory)
        let playlistData = try Data(contentsOf: playlistsURL)
        let playlistDecoder = JSONDecoder()
        playlistDecoder.dateDecodingStrategy = .iso8601
        let persistedPlaylists = try playlistDecoder.decode([Playlist].self, from: playlistData)
        XCTAssertTrue(persistedPlaylists.first?.contains(track.id) ?? false)
    }

    func testDecodingLegacyManifestWithoutStatsFields() throws {
        // 新フィールド追加前の library.json がそのまま読めること(後方互換)
        let legacyJSON = """
        [
          {
            "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "title": "Old Track",
            "originalFilename": "old.wav",
            "storedFilename": "old-abc.wav",
            "importedAt": "2025-01-01T00:00:00Z",
            "duration": 120
          }
        ]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let tracks = try decoder.decode([AudioTrack].self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(tracks.count, 1)
        let track = try XCTUnwrap(tracks.first)
        XCTAssertEqual(track.title, "Old Track")
        XCTAssertNil(track.contentHash)
        XCTAssertNil(track.playCount)
        XCTAssertNil(track.lastPlayedAt)
        XCTAssertNil(track.playHourCounts)
        XCTAssertNil(track.notes)
    }
}
