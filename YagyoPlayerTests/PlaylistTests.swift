import XCTest
@testable import YagyoPlayer

final class PlaylistTests: XCTestCase {
    func testAddIgnoresDuplicates() {
        var playlist = Playlist(name: "Night Parade")
        let trackID = UUID()

        playlist.add(trackID)
        playlist.add(trackID)

        XCTAssertEqual(playlist.trackIDs, [trackID])
        XCTAssertTrue(playlist.contains(trackID))
    }

    func testRemoveDeletesTrack() {
        let trackID = UUID()
        var playlist = Playlist(name: "Night Parade", trackIDs: [trackID])

        playlist.remove(trackID)

        XCTAssertTrue(playlist.trackIDs.isEmpty)
        XCTAssertFalse(playlist.contains(trackID))
    }

    func testMoveSwapsNeighbors() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var playlist = Playlist(name: "Night Parade", trackIDs: [first, second, third])

        playlist.move(third, by: -1)

        XCTAssertEqual(playlist.trackIDs, [first, third, second])
    }

    func testMoveOutOfBoundsIsIgnored() {
        let first = UUID()
        let second = UUID()
        var playlist = Playlist(name: "Night Parade", trackIDs: [first, second])

        playlist.move(first, by: -1)
        playlist.move(second, by: 1)

        XCTAssertEqual(playlist.trackIDs, [first, second])
    }

    func testCodableRoundTrip() throws {
        let playlist = Playlist(name: "Night Parade", trackIDs: [UUID(), UUID()])

        let data = try JSONEncoder().encode(playlist)
        let decoded = try JSONDecoder().decode(Playlist.self, from: data)

        XCTAssertEqual(decoded, playlist)
    }

    func testAddTrackIgnoresTrackMissingFromLibrary() throws {
        let documentsDirectory = try makeTemporaryDocumentsDirectory()
        defer { try? FileManager.default.removeItem(at: documentsDirectory) }

        let store = AudioLibraryStore(fileManager: .default, documentsDirectory: documentsDirectory)
        store.load()

        let playlist = try XCTUnwrap(store.createPlaylist(named: "Night Parade"))
        let orphanTrack = AudioTrack(
            title: "Orphan",
            originalFilename: "orphan.mp3",
            storedFilename: "orphan.mp3"
        )

        store.addTrack(orphanTrack, to: playlist)

        XCTAssertEqual(store.playlists.first?.trackIDs, [])
    }

    func testLoadSanitizesMissingTrackIDsFromPlaylists() throws {
        let documentsDirectory = try makeTemporaryDocumentsDirectory()
        defer { try? FileManager.default.removeItem(at: documentsDirectory) }

        let fileManager = FileManager.default
        let libraryDirectory = documentsDirectory.appending(path: "YagyoLibrary", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)

        let validTrack = AudioTrack(
            id: UUID(),
            title: "Valid",
            originalFilename: "valid.mp3",
            storedFilename: "valid.mp3",
            importedAt: Date(timeIntervalSince1970: 0)
        )
        let playlist = Playlist(
            name: "Night Parade",
            trackIDs: [validTrack.id, UUID()]
        )

        try configuredEncoder().encode([validTrack]).write(
            to: libraryDirectory.appending(path: "library.json", directoryHint: .notDirectory),
            options: [.atomic]
        )
        try configuredEncoder().encode([playlist]).write(
            to: libraryDirectory.appending(path: "playlists.json", directoryHint: .notDirectory),
            options: [.atomic]
        )

        let store = AudioLibraryStore(fileManager: fileManager, documentsDirectory: documentsDirectory)
        store.activePlaylistID = UUID()
        store.load()

        XCTAssertEqual(store.playlists.first?.trackIDs, [validTrack.id])
        XCTAssertNil(store.activePlaylistID)

        let reloaded = try configuredDecoder().decode(
            [Playlist].self,
            from: Data(contentsOf: libraryDirectory.appending(path: "playlists.json", directoryHint: .notDirectory))
        )
        XCTAssertEqual(reloaded.first?.trackIDs, [validTrack.id])
    }

    private func makeTemporaryDocumentsDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "YagyoPlayerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func configuredEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func configuredDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
