import AppIntents
import Foundation

enum PlayerDestination: String, AppEnum {
    case library
    case nowPlaying

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Player Destination")

    static let caseDisplayRepresentations: [PlayerDestination: DisplayRepresentation] = [
        .library: "Library",
        .nowPlaying: "Now Playing"
    ]
}

struct OpenYagyoPlayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Yagyo Player"
    static let description = IntentDescription("Open the local audio library or now playing view.")
    static let openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: PlayerDestination

    init() {
        destination = .library
    }

    init(destination: PlayerDestination) {
        self.destination = destination
    }

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(destination.routeURL))
    }
}

struct ContinueYagyoTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Last Yagyo Track"
    static let description = IntentDescription("Open Yagyo Player so the most recent local track can resume.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "yagyo://continue")!))
    }
}

struct YagyoPlayerShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenYagyoPlayerIntent(destination: .library),
            phrases: [
                "Open \(.applicationName)",
                "Show my Yagyo library in \(.applicationName)"
            ],
            shortTitle: "Open Library",
            systemImageName: "music.note.list"
        )

        AppShortcut(
            intent: ContinueYagyoTrackIntent(),
            phrases: [
                "Continue \(.applicationName)",
                "Resume my Yagyo track in \(.applicationName)"
            ],
            shortTitle: "Continue Track",
            systemImageName: "play.circle"
        )
    }
}

private extension PlayerDestination {
    var routeURL: URL {
        switch self {
        case .library:
            URL(string: "yagyo://library")!
        case .nowPlaying:
            URL(string: "yagyo://nowPlaying")!
        }
    }
}
