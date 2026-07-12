import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import YagyoPlayer

final class TomoshibiSliderTests: XCTestCase {
    // MARK: - タップ/ドラッグ位置 → 値の写像

    func testFractionMapsMidpointToHalf() {
        XCTAssertEqual(TomoshibiSlider.fraction(at: 50, width: 100), 0.5, accuracy: 1e-9)
    }

    func testFractionClampsLeftOfTrackToZero() {
        XCTAssertEqual(TomoshibiSlider.fraction(at: -10, width: 100), 0)
    }

    func testFractionClampsRightOfTrackToOne() {
        XCTAssertEqual(TomoshibiSlider.fraction(at: 150, width: 100), 1)
    }

    func testFractionGuardsAgainstZeroWidth() {
        XCTAssertEqual(TomoshibiSlider.fraction(at: 10, width: 0), 0)
    }

    // ノブ中心の可動域は [r, width - r]。表示(knobCenterX)と操作(fraction)が
    // 同じ写像でないと、ノブ上からのドラッグ開始で値が跳ぶ(Copilot指摘)。

    func testFractionMapsKnobCenterAtLeftEdgeToZero() {
        let radius = TomoshibiSlider.knobDiameter / 2
        XCTAssertEqual(TomoshibiSlider.fraction(at: radius, width: 100), 0)
    }

    func testFractionMapsKnobCenterAtRightEdgeToOne() {
        let radius = TomoshibiSlider.knobDiameter / 2
        XCTAssertEqual(TomoshibiSlider.fraction(at: 100 - radius, width: 100), 1)
    }

    // MARK: - VoiceOver adjustable の増減

    func testNudgeIncrementsByStep() {
        XCTAssertEqual(TomoshibiSlider.nudged(0.5, direction: .increment), 0.55, accuracy: 1e-9)
    }

    func testNudgeDecrementsByStep() {
        XCTAssertEqual(TomoshibiSlider.nudged(0.5, direction: .decrement), 0.45, accuracy: 1e-9)
    }

    func testNudgeClampsAtUpperBound() {
        XCTAssertEqual(TomoshibiSlider.nudged(0.98, direction: .increment), 1)
    }

    func testNudgeClampsAtLowerBound() {
        XCTAssertEqual(TomoshibiSlider.nudged(0.02, direction: .decrement), 0)
    }

    // MARK: - QA artifact(灯芯の実描画)

    @MainActor
    func testExportsTomoshibiSliderArtifact() throws {
        // ContentViewの音量行と同じ構成を代表値3つで描き、PNGをxcresultへ添付する
        // (帳のtestExportsTobariScreenArtifactと同じ証跡パターン)。
        let view = VStack(spacing: 28) {
            ForEach([0.0, 0.35, 0.88], id: \.self) { volume in
                VStack(alignment: .leading, spacing: 6) {
                    Text("音量 \(Int(volume * 100))%")
                        .font(.caption)
                        .foregroundStyle(YagyoColor.dim)
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.1.fill")
                            .foregroundStyle(YagyoColor.dim)
                        TomoshibiSlider(value: .constant(volume))
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(YagyoColor.dim)
                    }
                    .font(.caption)
                }
            }
        }
        .ritualPanel(radius: 24, padding: 16)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { YagyoBackdrop(isUshimitsu: false) }

        try exportWindowArtifact(
            rootView: view,
            windowHeight: 852,
            attachmentName: "tomoshibi-slider.png"
        )
    }

    @MainActor
    func testExportsContentViewWithTomoshibiSliderArtifact() throws {
        // 実際のContentView(空ライブラリ)を縦長ウィンドウへ全高で描き、
        // 音量行が標準Sliderから灯芯へ置き換わった統合後の姿を写す。
        let store = AudioLibraryStore(
            documentsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("tomoshibi-content-artifact-\(UUID().uuidString)", isDirectory: true)
        )
        let view = ContentView()
            .environmentObject(store)
            .environmentObject(PlaybackController())
            .environmentObject(AppRouter())

        try exportWindowArtifact(
            rootView: view,
            windowHeight: 2200,
            attachmentName: "tomoshibi-contentview.png"
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
