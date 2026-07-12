import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest

/// Simulator実ウィンドウでの実描画artifactを撮る共通ヘルパー。
/// ImageRendererはScrollView内のコンテンツを描画せず、シーン未接続の
/// UIWindowは真っ白になるため、windowScene接続+drawHierarchy方式で統一する
/// (帳のartifactが初出のパターン)。
extension XCTestCase {
    @MainActor
    func exportWindowArtifact(
        rootView: some View,
        windowHeight: CGFloat = 852,
        attachmentName: String
    ) throws {
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
    func pixelSpread(of image: UIImage) -> Int {
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
