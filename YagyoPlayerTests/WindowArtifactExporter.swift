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
        windowWidth: CGFloat = 393,
        windowHeight: CGFloat = 852,
        interfaceStyle: UIUserInterfaceStyle = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        settlingDelay: TimeInterval = 0.7,
        scrollToBottom: Bool = false,
        expectedTabTitles: [String]? = nil,
        attachmentName: String
    ) throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first,
            "テストホストのUIWindowSceneが見つかりません"
        )
        let host = UIHostingController(
            rootView: rootView.environment(\.dynamicTypeSize, dynamicTypeSize)
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        window.overrideUserInterfaceStyle = interfaceStyle
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settlingDelay))

        if scrollToBottom {
            XCTAssertTrue(
                scrollLargestVerticalContentToBottom(in: window),
                "下端artifact用の縦ScrollViewが見つかりません"
            )
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        }

        let tabItemFrames = expectedTabTitles.map {
            assertVisibleTabTitles($0, in: window)
        } ?? []

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true

        if let expectedTabTitles {
            for (title, frame) in zip(expectedTabTitles, tabItemFrames) {
                XCTAssertGreaterThan(
                    pixelSpread(of: image, in: frame.insetBy(dx: 10, dy: 3)),
                    80,
                    "native tab barの\(title)が画像へ描画されていません"
                )
            }
        }

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

    @MainActor
    private func assertVisibleTabTitles(_ expectedTitles: [String], in window: UIWindow) -> [CGRect] {
        let tabBars = descendants(of: UITabBar.self, in: window)
        guard let tabBar = tabBars.first else {
            XCTFail("native UITabBarが実描画ツリーに見つかりません")
            return []
        }

        XCTAssertEqual(tabBar.items?.compactMap(\.title), expectedTitles)

        let candidateFrames = descendants(of: UIControl.self, in: tabBar)
            .filter {
                let className = String(describing: type(of: $0))
                return className.contains("Tab")
                    && className.contains("Button")
                    && !$0.isHidden
                    && $0.alpha > 0.01
            }
            .map { $0.convert($0.bounds, to: window) }
            .sorted { $0.midX < $1.midX }

        var uniqueFrames: [CGRect] = []
        for frame in candidateFrames {
            if !uniqueFrames.contains(where: { abs($0.midX - frame.midX) < 1 }) {
                uniqueFrames.append(frame)
            }
        }
        XCTAssertEqual(uniqueFrames.count, expectedTitles.count, "native tab barの可視ボタン数が仕様と異なります")
        return uniqueFrames
    }

    @MainActor
    private func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        var result = root.subviews.compactMap { $0 as? T }
        for child in root.subviews {
            result.append(contentsOf: descendants(of: type, in: child))
        }
        return result
    }

    @MainActor
    private func scrollLargestVerticalContentToBottom(in window: UIWindow) -> Bool {
        let candidates = descendants(of: UIScrollView.self, in: window)
            .filter {
                !$0.isHidden
                    && $0.alpha > 0.01
                    && $0.contentSize.height > $0.bounds.height + 1
            }
        guard let scrollView = candidates.max(by: {
            ($0.contentSize.height - $0.bounds.height) < ($1.contentSize.height - $1.bounds.height)
        }) else { return false }

        let maximumY = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: maximumY),
            animated: false
        )
        scrollView.layoutIfNeeded()
        return true
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

    private func pixelSpread(of image: UIImage, in rect: CGRect) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let pixelRect = CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        guard let crop = cgImage.cropping(to: pixelRect) else { return 0 }

        let width = 16
        let height = 12
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.interpolationQuality = .medium
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minimum = UInt8.max
        var maximum = UInt8.min
        for index in stride(from: 0, to: buffer.count, by: 4) {
            for channel in index..<(index + 3) {
                minimum = min(minimum, buffer[channel])
                maximum = max(maximum, buffer[channel])
            }
        }
        return Int(maximum) - Int(minimum)
    }
}
