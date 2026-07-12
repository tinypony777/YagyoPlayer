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

    @MainActor
    private func exportWindowArtifact(
        rootView: some View,
        windowHeight: CGFloat,
        attachmentName: String
    ) throws {
        // ImageRendererはScrollView内のコンテンツを描画しないため、
        // 実ウィンドウにホストしてレイアウトさせてから drawHierarchy で写す。
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first,
            "テストホストのUIWindowSceneが見つかりません"
        )
        let host = UIHostingController(rootView: rootView)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: windowHeight)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true

        // ほぼ単色(真っ白/真っ黒)なら描画に失敗している — artifactを黙って残さない。
        XCTAssertGreaterThan(
            pixelSpread(of: image), 60,
            "\(attachmentName) がほぼ単色 — 描画に失敗しています"
        )
        let data = try XCTUnwrap(image.pngData(), "PNGへ変換できません")
        XCTAssertFalse(data.isEmpty)

        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: UTType.png.identifier
        )
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 16x16へ縮小したときの画素値の広がり。単色画像は0に近い。
    private func pixelSpread(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let side = 16
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &buffer,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let minimum = buffer.min(), let maximum = buffer.max() else { return 0 }
        return Int(maximum) - Int(minimum)
    }
}
