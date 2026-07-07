import Foundation

@MainActor
final class AppRouter: ObservableObject {
    enum PendingAction {
        case showLibrary
        case showNowPlaying
        case continueLastTrack
    }

    @Published var pendingAction: PendingAction?

    @discardableResult
    func handle(url: URL) -> PendingAction? {
        guard url.scheme == "yagyo" else { return nil }

        switch url.host {
        case "continue":
            pendingAction = .continueLastTrack
        case "library":
            pendingAction = .showLibrary
        case "nowPlaying":
            pendingAction = .showNowPlaying
        default:
            pendingAction = nil
        }

        return pendingAction
    }
}
