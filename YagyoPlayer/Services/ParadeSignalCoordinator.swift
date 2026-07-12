import Combine
import Foundation

enum ParadeSignalResetReason: Sendable {
    case trackLoadStarted, loadFailure, playFailure, pause, seek, stop
}

@MainActor
final class ParadeSignalCoordinator: ObservableObject {
    @Published private(set) var snapshot = ParadeSignalSnapshot()
    private var reducer = ParadeSignalReducer()

    func ingest(level: Double?, isPlaying: Bool, sampledAt: TimeInterval) {
        snapshot = reducer.ingest(
            ParadeSignalInput(isPlaying: isPlaying, level: level, sampledAt: sampledAt)
        )
    }

    func reset(reason _: ParadeSignalResetReason, isPlaying: Bool) {
        snapshot = reducer.reset(isPlaying: isPlaying)
    }
}
