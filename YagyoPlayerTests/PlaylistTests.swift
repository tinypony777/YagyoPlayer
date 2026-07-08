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
}
