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
