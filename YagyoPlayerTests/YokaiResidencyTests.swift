import UIKit
import XCTest
@testable import YagyoPlayer

final class YokaiResidencyTests: XCTestCase {
    func testRosterOrderIsACompatibilityContract() {
        XCTAssertEqual(
            YokaiResidency.stableSpriteIDs,
            ["oni", "mokugyo", "kasa", "kappa", "kitsune", "tengu", "yuki", "biwa"]
        )
    }

    func testKnownLegacyUUIDStillMapsToYuki() throws {
        let id = try XCTUnwrap(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertEqual(YokaiResidency.spriteID(for: id), "yuki")
    }

    func testResidentLeadsWithoutDuplication() {
        let ids = YokaiResidency.processionIDs(residentID: "kasa", isUshimitsu: false)
        XCTAssertEqual(ids.first, "kasa")
        XCTAssertEqual(ids.count, 8)
        XCTAssertEqual(Set(ids).count, 8)
        XCTAssertEqual(Array(ids.dropFirst()), ["oni", "mokugyo", "kappa", "kitsune", "tengu", "yuki", "biwa"])
    }

    func testUnknownResidentFallsBackAndUshimitsuAppendsHitotsume() {
        XCTAssertEqual(
            YokaiResidency.processionIDs(residentID: "unknown", isUshimitsu: true),
            YokaiResidency.stableSpriteIDs + ["hitotsume"]
        )
    }

    func testWoodblockGalleryCoversStableResidentsAndLoadsEveryApprovedAsset() {
        XCTAssertEqual(
            WoodblockYokaiGallery.all.map(\.id),
            YokaiResidency.stableSpriteIDs + ["hitotsume"]
        )

        for asset in WoodblockYokaiGallery.all {
            let image = UIImage(named: asset.assetName)
            XCTAssertNotNil(image, asset.assetName)
            XCTAssertTrue(asset.isAvailable, asset.assetName)
            XCTAssertGreaterThan(asset.contentRect.width, 0, asset.id)
            XCTAssertGreaterThan(asset.contentRect.height, 0, asset.id)
            XCTAssertGreaterThanOrEqual(asset.contentRect.minX, 0, asset.id)
            XCTAssertGreaterThanOrEqual(asset.contentRect.minY, 0, asset.id)
            XCTAssertLessThanOrEqual(
                asset.contentRect.maxX,
                WoodblockYokaiAsset.logicalCanvasSize,
                asset.id
            )
            XCTAssertLessThanOrEqual(
                asset.contentRect.maxY,
                WoodblockYokaiAsset.logicalCanvasSize,
                asset.id
            )

            guard let alphaBounds = image.flatMap(alphaBoundsInTopLeftCoordinates) else {
                XCTFail("\(asset.assetName) にalpha画素がありません")
                continue
            }
            let scale = WoodblockYokaiAsset.logicalCanvasSize / 442
            let normalizedBounds = CGRect(
                x: alphaBounds.minX * scale,
                y: alphaBounds.minY * scale,
                width: alphaBounds.width * scale,
                height: alphaBounds.height * scale
            )
            XCTAssertEqual(normalizedBounds.minX, asset.contentRect.minX, accuracy: 0.002, asset.id)
            XCTAssertEqual(normalizedBounds.minY, asset.contentRect.minY, accuracy: 0.002, asset.id)
            XCTAssertEqual(normalizedBounds.width, asset.contentRect.width, accuracy: 0.002, asset.id)
            XCTAssertEqual(normalizedBounds.height, asset.contentRect.height, accuracy: 0.002, asset.id)
        }
    }

    /// CGContextのraw rowは下端起点なので、表示座標と同じ左上原点へ反転して返す。
    private func alphaBoundsInTopLeftCoordinates(_ image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minRawY = height
        var maxX = -1
        var maxRawY = -1
        for rawY in 0..<height {
            for x in 0..<width where pixels[(rawY * width + x) * 4 + 3] > 0 {
                minX = min(minX, x)
                minRawY = min(minRawY, rawY)
                maxX = max(maxX, x)
                maxRawY = max(maxRawY, rawY)
            }
        }
        guard maxX >= minX, maxRawY >= minRawY else { return nil }

        let topY = height - 1 - maxRawY
        let bottomY = height - 1 - minRawY
        return CGRect(
            x: minX,
            y: topY,
            width: maxX - minX + 1,
            height: bottomY - topY + 1
        )
    }
}
