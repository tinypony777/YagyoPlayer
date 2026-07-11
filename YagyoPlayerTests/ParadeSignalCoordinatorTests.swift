import XCTest
@testable import YagyoPlayer

@MainActor
final class ParadeSignalCoordinatorTests: XCTestCase {
    func testIngestPublishesReducerSnapshot() {
        let coordinator = ParadeSignalCoordinator()

        coordinator.ingest(level: 0.2, isPlaying: true, sampledAt: 0)

        XCTAssertEqual(coordinator.snapshot.activity, .normal)
        XCTAssertEqual(coordinator.snapshot.level, 0.2)
    }

    func testUnavailableAndSemanticResetDoNotMasqueradeAsQuiet() {
        let coordinator = ParadeSignalCoordinator()

        coordinator.ingest(level: nil, isPlaying: true, sampledAt: 0)
        XCTAssertEqual(coordinator.snapshot.activity, .unavailable)

        coordinator.reset(reason: .seek, isPlaying: true)
        XCTAssertEqual(coordinator.snapshot.activity, .unavailable)

        coordinator.reset(reason: .pause, isPlaying: false)
        XCTAssertEqual(coordinator.snapshot.activity, .stopped)
    }
}
