import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import YagyoPlayer

final class YagyoTabTests: XCTestCase {
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
            let store = AudioLibraryStore(
                documentsDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("tab-artifact-\(tab.rawValue)-\(UUID().uuidString)", isDirectory: true)
            )
            let view = ContentView(initialTab: tab)
                .environmentObject(store)
                .environmentObject(PlaybackController())
                .environmentObject(AppRouter())

            try exportWindowArtifact(
                rootView: view,
                windowHeight: 852,
                attachmentName: "tab-\(tab.rawValue).png"
            )
        }
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
            windowHeight: 852,
            attachmentName: "mini-akari.png"
        )
    }

}
