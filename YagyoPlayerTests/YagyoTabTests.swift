import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import YagyoPlayer

final class YagyoTabTests: XCTestCase {
    private struct ArtifactFixture {
        let store: AudioLibraryStore
        let root: URL
    }

    // MARK: - 間取り(タブ構成)は仕様§4.2の承認どおり

    func testThreeTabsInApprovedOrder() {
        XCTAssertEqual(YagyoTab.allCases, [.yagyo, .gyoretsu, .makimono])
    }

    func testTitlesMatchSpec() {
        XCTAssertEqual(YagyoTab.yagyo.title, "夜行")
        XCTAssertEqual(YagyoTab.gyoretsu.title, "行列")
        XCTAssertEqual(YagyoTab.makimono.title, "巻物")
    }

    func testIconsMatchSpec() {
        XCTAssertEqual(YagyoTab.yagyo.icon, "house")
        XCTAssertEqual(YagyoTab.gyoretsu.icon, "list.bullet")
        XCTAssertEqual(YagyoTab.makimono.icon, "scroll")
    }

    // URLショートカットの行き先: library=行列、再生系=夜行(Codex指摘対応)。
    func testDestinationRoutesPendingActionsToTabs() {
        XCTAssertEqual(YagyoTab.destination(for: .showLibrary), .gyoretsu)
        XCTAssertEqual(YagyoTab.destination(for: .showNowPlaying), .yagyo)
        XCTAssertEqual(YagyoTab.destination(for: .continueLastTrack), .yagyo)
    }

    // ミニ灯りは行列/巻物だけ。夜行タブは本体の操作面があるので出さない。
    func testMiniAkariShowsOnlyOutsideYagyo() {
        XCTAssertFalse(YagyoTab.yagyo.showsMiniAkari)
        XCTAssertTrue(YagyoTab.gyoretsu.showsMiniAkari)
        XCTAssertTrue(YagyoTab.makimono.showsMiniAkari)
    }

    // MARK: - QA artifact(3タブとミニ灯りの実描画)

    @MainActor
    func testExportsYagyoTabArtifacts() throws {
        for tab in YagyoTab.allCases {
            let fixture = try makeArtifactFixture(suffix: tab.rawValue)
            defer { try? FileManager.default.removeItem(at: fixture.root) }

            let router = AppRouter()
            // iOS 27のTabViewは中間タブをcold start選択すると、未訪問の末尾itemを
            // 最初の描画だけ省く。製品と同じ夜行起点のroutingで行列を撮る。
            let initialTab: YagyoTab = tab == .gyoretsu ? .yagyo : tab

            let view = ContentView(initialTab: initialTab)
                .environmentObject(fixture.store)
                .environmentObject(PlaybackController())
                .environmentObject(router)

            if tab == .gyoretsu {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    router.pendingAction = .showLibrary
                }
            }

            try exportWindowArtifact(
                rootView: view,
                windowWidth: 402,
                windowHeight: 874,
                interfaceStyle: .light,
                settlingDelay: 2.0,
                expectedTabTitles: YagyoTab.allCases.map(\.title),
                attachmentName: "tab-\(tab.rawValue).png"
            )
        }
    }

    @MainActor
    func testExports17eTabArtifacts() throws {
        for tab in YagyoTab.allCases {
            let fixture = try makeArtifactFixture(suffix: "17e-\(tab.rawValue)")
            defer { try? FileManager.default.removeItem(at: fixture.root) }

            let router = AppRouter()
            let initialTab: YagyoTab = tab == .gyoretsu ? .yagyo : tab

            let view = ContentView(
                initialTab: initialTab,
                initiallyExpandedPlaylistID: tab == .makimono ? fixture.store.playlists.first?.id : nil
            )
                .environmentObject(fixture.store)
                .environmentObject(PlaybackController())
                .environmentObject(router)

            if tab == .gyoretsu {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    router.pendingAction = .showLibrary
                }
            }

            try exportWindowArtifact(
                rootView: view,
                windowWidth: 390,
                windowHeight: 844,
                interfaceStyle: .light,
                settlingDelay: 2.0,
                expectedTabTitles: YagyoTab.allCases.map(\.title),
                attachmentName: "tab-17e-\(tab.rawValue).png"
            )
        }
    }

    @MainActor
    func testExportsAccessibilityLargeGyoretsuArtifact() throws {
        let fixture = try makeArtifactFixture(suffix: "accessibility-large-gyoretsu")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let view = ContentView(initialTab: .gyoretsu)
            .environmentObject(fixture.store)
            .environmentObject(PlaybackController())
            .environmentObject(AppRouter())
            .environment(\.dynamicTypeSize, .accessibility3)

        try exportWindowArtifact(
            rootView: view,
            windowWidth: 390,
            windowHeight: 844,
            interfaceStyle: .light,
            dynamicTypeSize: .accessibility3,
            settlingDelay: 2.0,
            expectedTabTitles: YagyoTab.allCases.map(\.title),
            attachmentName: "tab-gyoretsu-accessibility-large.png"
        )
    }

    @MainActor
    func testExportsAccessibilityLargeYagyoArtifact() throws {
        let fixture = try makeArtifactFixture(suffix: "accessibility-large")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let view = ContentView(initialTab: .yagyo)
            .environmentObject(fixture.store)
            .environmentObject(PlaybackController())
            .environmentObject(AppRouter())
            .environment(\.dynamicTypeSize, .accessibility3)

        try exportWindowArtifact(
            rootView: view,
            windowWidth: 390,
            windowHeight: 844,
            interfaceStyle: .light,
            dynamicTypeSize: .accessibility3,
            attachmentName: "tab-yagyo-accessibility-large.png"
        )
    }

    @MainActor
    func testExportsUshimitsuYagyoArtifact() throws {
        let fixture = try makeArtifactFixture(suffix: "ushimitsu")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let view = ContentView(initialTab: .yagyo, startsInUshimitsu: true)
            .environmentObject(fixture.store)
            .environmentObject(PlaybackController())
            .environmentObject(AppRouter())

        try exportWindowArtifact(
            rootView: view,
            windowWidth: 402,
            windowHeight: 874,
            interfaceStyle: .light,
            attachmentName: "tab-yagyo-ushimitsu.png"
        )
    }

    @MainActor
    func testExportsMiniAkariArtifact() throws {
        let view = VStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 6) {
                Text("再生中(朱の芯が灯る)")
                    .font(.caption)
                    .foregroundStyle(YagyoColor.dim)
                    .padding(.horizontal, 18)
                MiniAkariBar(title: "宵の底 (rough mix 3)", isPlaying: true, onToggle: {}, onOpenYagyo: {})
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("一時停止中")
                    .font(.caption)
                    .foregroundStyle(YagyoColor.dim)
                    .padding(.horizontal, 18)
                MiniAkariBar(title: "宵の底 (rough mix 3)", isPlaying: false, onToggle: {}, onOpenYagyo: {})
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { YagyoBackdrop(isUshimitsu: false) }

        try exportWindowArtifact(
            rootView: view,
            windowWidth: 402,
            windowHeight: 874,
            interfaceStyle: .light,
            attachmentName: "mini-akari.png"
        )
    }

    @MainActor
    private func makeArtifactFixture(suffix: String) throws -> ArtifactFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tab-artifact-\(suffix)-\(UUID().uuidString)", isDirectory: true)
        let libraryDirectory = root.appendingPathComponent("YagyoLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)

        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let tracks = [
            AudioTrack(
                id: firstID,
                title: "宵の底 (rough mix 3)",
                originalFilename: "yoi-no-soko-v3.wav",
                storedFilename: "yoi-no-soko-v3.wav",
                importedAt: Date(timeIntervalSince1970: 1_752_192_000),
                duration: 217,
                artist: "tinypony",
                notes: "True Peakとモノ互換を確認"
            ),
            AudioTrack(
                id: secondID,
                title: "雨の茶舗",
                originalFilename: "ame-no-chaho.aiff",
                storedFilename: "ame-no-chaho.aiff",
                importedAt: Date(timeIntervalSince1970: 1_752_105_600),
                duration: 252,
                artist: "mameyudoufu"
            )
        ]
        let playlists = [
            Playlist(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                name: "明治の夜行",
                createdAt: Date(timeIntervalSince1970: 1_752_192_000),
                trackIDs: [firstID, secondID]
            )
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(tracks)
            .write(to: libraryDirectory.appendingPathComponent("library.json"), options: .atomic)
        try encoder.encode(playlists)
            .write(to: libraryDirectory.appendingPathComponent("playlists.json"), options: .atomic)

        let store = AudioLibraryStore(documentsDirectory: root)
        store.load()
        return ArtifactFixture(store: store, root: root)
    }

}
