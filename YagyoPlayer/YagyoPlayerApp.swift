import Foundation
import SwiftUI

@main
@MainActor
struct YagyoPlayerApp: App {
    @StateObject private var library = AudioLibraryStore()
    @StateObject private var player: PlaybackController
    @StateObject private var router = AppRouter()

    init() {
        #if DEBUG
        let usesLegacyBackend = ProcessInfo.processInfo.arguments.contains(
            "-legacy-playback-backend"
        )
        if #available(iOS 27.0, *), !usesLegacyBackend {
            _player = StateObject(
                wrappedValue: PlaybackController(
                    backend: AVAudioEngineFixedEQPlaybackBackend()
                )
            )
        } else {
            _player = StateObject(wrappedValue: PlaybackController())
        }
        #else
        _player = StateObject(wrappedValue: PlaybackController())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-step3-fixed-eq-preview") {
                FixedEQAuditionPreviewHarness()
            } else if ProcessInfo.processInfo.arguments.contains("-step4-parade-preview") {
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
