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
        // 実際のContentView(空ライブラリ)を実寸ウィンドウで描き、音量行が
        // 標準Sliderから灯芯へ置き換わった統合後の姿を写す。タブ化で夜行は
        // 1画面レイアウトになったため、縦長ではなく実機と同じ高さで撮る。
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
            windowHeight: 852,
            attachmentName: "tomoshibi-contentview.png"
        )
    }

}
