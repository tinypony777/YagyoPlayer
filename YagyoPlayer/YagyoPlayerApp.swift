import SwiftUI

@main
struct YagyoPlayerApp: App {
    @StateObject private var library = AudioLibraryStore()
    @StateObject private var player = PlaybackController()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(router)
                .task {
                    library.load()
                    player.installRemoteCommands(library: library)
                }
                .onOpenURL { url in
                    let action = router.handle(url: url)
                    if action == .continueLastTrack {
                        player.playMostRecent(from: library)
                    }
                }
        }
    }
}
