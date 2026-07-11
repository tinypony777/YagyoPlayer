import XCTest
@testable import YagyoPlayer

final class PixelSpriteContractTests: XCTestCase {
    func testKarakasaHasExactlyEightSemanticFrames() {
        XCTAssertEqual(KarakasaSpriteArt.idle.count, 1)
        XCTAssertEqual(KarakasaSpriteArt.walk.count, 4)
        XCTAssertEqual(KarakasaSpriteArt.hush.count, 1)
        XCTAssertEqual(KarakasaSpriteArt.strong.count, 2)
    }

    func testEveryKarakasaFrameUsesTheSharedCanvasPaletteAndGroundAnchor() {
        for definition in KarakasaSpriteArt.allDefinitions {
            XCTAssertEqual(definition.rows.count, 48, definition.name)
            XCTAssertTrue(definition.rows.allSatisfy { $0.utf8.count == 40 }, definition.name)
            XCTAssertEqual(definition.anchorX, 20, definition.name)
            XCTAssertEqual(definition.baselineY, 45, definition.name)
            XCTAssertLessThanOrEqual(definition.usedColorCount, 12, definition.name)
            XCTAssertTrue(definition.unknownSymbols.isEmpty, definition.name)
            XCTAssertTrue(definition.hasTransparentTopAndSideMargins, definition.name)
            XCTAssertLessThanOrEqual(definition.lowestOpaqueY, definition.baselineY, definition.name)
        }
    }

    func testRenderedKarakasaFramesStayFortyByFortyEight() {
        for frame in KarakasaSpriteArt.allDefinitions.map({ PixelArt.frame($0) }) {
            XCTAssertEqual(frame.pixelWidth, 40)
            XCTAssertEqual(frame.pixelHeight, 48)
        }
    }
}
