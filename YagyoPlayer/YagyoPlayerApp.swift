import Foundation
import SwiftUI

@main
struct YagyoPlayerApp: App {
    @StateObject private var library = AudioLibraryStore()
    @StateObject private var player = PlaybackController()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-step4-parade-preview") {
                ParadePreviewHarness()
            } else {
                productionRoot
            }
            #else
            productionRoot
            #endif
        }
    }

    private var productionRoot: some View {
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
