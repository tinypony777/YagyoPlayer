import XCTest
@testable import YagyoPlayer

@MainActor
final class LibraryConfidenceTests: XCTestCase {
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

    private func writeLibraryManifest(_ json: String) throws {
        let libraryDirectory = temporaryDirectory.appending(path: "YagyoLibrary", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        try Data(json.utf8)
            .write(to: libraryDirectory.appending(path: "library.json", directoryHint: .notDirectory))
    }

    func testUpdateMetadataPersistsEditableFields() async throws {
        let store = makeStore()
        store.load()

        let source = try writeSourceFile(named: "moon-demo.wav", contents: "metadata-audio")
        await store.importAudioFiles(from: [source])
        let track = try XCTUnwrap(store.tracks.first)

        store.updateMetadata(
            for: track.id,
            title: "月下のデモ",
            artist: "Ryusei",
            artworkFilename: "moon-card.png",
            notes: "Aメロの低域を確認"
        )

        let updated = try XCTUnwrap(store.tracks.first)
        XCTAssertEqual(updated.title, "月下のデモ")
        XCTAssertEqual(updated.artist, "Ryusei")
        XCTAssertEqual(updated.artworkFilename, "moon-card.png")
        XCTAssertEqual(updated.notes, "Aメロの低域を確認")
        XCTAssertNil(store.persistenceErrorMessage)

        let reloaded = makeStore()
        reloaded.load()
        let persisted = try XCTUnwrap(reloaded.tracks.first)
        XCTAssertEqual(persisted.title, "月下のデモ")
        XCTAssertEqual(persisted.artist, "Ryusei")
        XCTAssertEqual(persisted.artworkFilename, "moon-card.png")
        XCTAssertEqual(persisted.notes, "Aメロの低域を確認")
    }

    func testUpdateMetadataRollsBackAndReportsFailureWhenManifestCannotBeSaved() async throws {
        let store = makeStore()
        store.load()

        let source = try writeSourceFile(named: "blocked-save.wav", contents: "metadata-audio")
        await store.importAudioFiles(from: [source])
        let track = try XCTUnwrap(store.tracks.first)

        let libraryDirectory = temporaryDirectory.appending(path: "YagyoLibrary", directoryHint: .isDirectory)
        let manifestURL = libraryDirectory.appending(path: "library.json", directoryHint: .notDirectory)
        try FileManager.default.removeItem(at: manifestURL)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false)

        let didSave = store.updateMetadata(
            for: track.id,
            title: "保存できない札",
            artist: "Ryusei",
            artworkFilename: nil,
            notes: "should roll back"
        )

        XCTAssertFalse(didSave)
        XCTAssertEqual(store.tracks.first?.title, track.title)
        XCTAssertEqual(store.tracks.first?.artist, track.artist)
        XCTAssertNotNil(store.persistenceErrorMessage)
    }

    func testFilteredTracksSearchesTitleArtistFilenameAndNotes() async throws {
        let store = makeStore()
        store.load()

        let first = try writeSourceFile(named: "moon.wav", contents: "moon-audio")
        let second = try writeSourceFile(named: "river.wav", contents: "river-audio")
        await store.importAudioFiles(from: [first, second])

        let moon = try XCTUnwrap(store.tracks.first { $0.originalFilename == "moon.wav" })
        let river = try XCTUnwrap(store.tracks.first { $0.originalFilename == "river.wav" })
        store.updateMetadata(for: moon.id, title: "月のデモ", artist: "Ryusei", artworkFilename: nil, notes: "低域チェック")
        store.updateMetadata(for: river.id, title: "川のデモ", artist: nil, artworkFilename: "river.png", notes: nil)

        XCTAssertEqual(store.filteredTracks(searchText: "Ryusei").map(\.id), [moon.id])
        XCTAssertEqual(store.filteredTracks(searchText: "低域").map(\.id), [moon.id])
        XCTAssertEqual(store.filteredTracks(searchText: "river.png").map(\.id), [river.id])
        XCTAssertEqual(store.filteredTracks(searchText: "river.wav").map(\.id), [river.id])
    }

    func testFilteredTracksSortsByTitleDurationAndPlaylistOrder() throws {
        let manifest = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "title": "Long Take",
            "originalFilename": "long.wav",
            "storedFilename": "long.wav",
            "importedAt": "2025-01-02T00:00:00Z",
            "duration": 300,
            "contentHash": "hash-long"
          },
          {
            "id": "00000000-0000-0000-0000-000000000002",
            "title": "Short Take",
            "originalFilename": "short.wav",
            "storedFilename": "short.wav",
            "importedAt": "2025-01-01T00:00:00Z",
            "duration": 30,
            "contentHash": "hash-short"
          }
        ]
        """
        try writeLibraryManifest(manifest)

        let store = makeStore()
        store.load()

        XCTAssertEqual(store.filteredTracks(sort: .titleAscending).map(\.title), ["Long Take", "Short Take"])
        XCTAssertEqual(store.filteredTracks(sort: .durationAscending).map(\.title), ["Short Take", "Long Take"])
        XCTAssertEqual(store.filteredTracks(sort: .durationDescending).map(\.title), ["Long Take", "Short Take"])

        let playlist = try XCTUnwrap(store.createPlaylist(named: "検聴順"))
        let short = try XCTUnwrap(store.tracks.first { $0.title == "Short Take" })
        let long = try XCTUnwrap(store.tracks.first { $0.title == "Long Take" })
        store.addTrack(short, to: playlist)
        store.addTrack(long, to: playlist)

        XCTAssertEqual(
            store.filteredTracks(sort: .playlistOrder, playlistID: playlist.id).map(\.title),
            ["Short Take", "Long Take"]
        )
    }

    func testDuplicateTrackGroupsExposeLegacyDuplicates() throws {
        let manifest = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "title": "Take A",
            "originalFilename": "take-a.wav",
            "storedFilename": "take-a.wav",
            "importedAt": "2025-01-01T00:00:00Z",
            "duration": 120,
            "contentHash": "same-hash"
          },
          {
            "id": "00000000-0000-0000-0000-000000000002",
            "title": "Take B",
            "originalFilename": "take-b.wav",
            "storedFilename": "take-b.wav",
            "importedAt": "2025-01-02T00:00:00Z",
            "duration": 120,
            "contentHash": "same-hash"
          }
        ]
        """
        try writeLibraryManifest(manifest)

        let store = makeStore()
        store.load()

        XCTAssertEqual(store.duplicateTrackGroups.count, 1)
        XCTAssertEqual(store.duplicateTrackGroups.first?.tracks.map(\.title), ["Take A", "Take B"])
    }
}
