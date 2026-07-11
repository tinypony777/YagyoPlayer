import XCTest
@testable import YagyoPlayer

private struct PixelPoint: Hashable {
    let x: Int
    let y: Int
}

private struct PixelBounds: Equatable {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
    var doubledCenterX: Int { minX + maxX }
}

private func points(
    in definition: PixelSpriteDefinition,
    symbols: Set<Character>,
    yRange: ClosedRange<Int>? = nil
) -> Set<PixelPoint> {
    Set(definition.rows.enumerated().flatMap { y, row in
        row.enumerated().compactMap { x, symbol in
            guard symbols.contains(symbol), yRange?.contains(y) ?? true else { return nil }
            return PixelPoint(x: x, y: y)
        }
    })
}

private func bounds(of points: Set<PixelPoint>) -> PixelBounds {
    PixelBounds(
        minX: points.map(\.x).min()!,
        maxX: points.map(\.x).max()!,
        minY: points.map(\.y).min()!,
        maxY: points.map(\.y).max()!
    )
}

private func componentCount(_ source: Set<PixelPoint>) -> Int {
    var remaining = source
    var count = 0
    while let start = remaining.first {
        count += 1
        var stack = [start]
        remaining.remove(start)
        while let point = stack.popLast() {
            let neighbors = [
                PixelPoint(x: point.x - 1, y: point.y),
                PixelPoint(x: point.x + 1, y: point.y),
                PixelPoint(x: point.x, y: point.y - 1),
                PixelPoint(x: point.x, y: point.y + 1),
            ]
            for neighbor in neighbors where remaining.remove(neighbor) != nil {
                stack.append(neighbor)
            }
        }
    }
    return count
}

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

    func testKarakasaPaletteIsReferenceFaithfulAndContainsNoLegacyPurple() {
        let approved: Set<UInt32> = [
            0x24160f, 0x8e2f2d, 0xc94545, 0xe45c5e, 0xf37a76, 0xfff3da,
            0xf18da6, 0xc85f7e, 0xf5d7c5, 0x80512f, 0x4a2e1f, 0xd5a32c,
        ]
        let banned: Set<UInt32> = [0x6e5aa8, 0x3f315f, 0x9f88d1, 0x2b203d]
        XCTAssertEqual(Set(KarakasaSpriteArt.palette.values), approved)
        XCTAssertTrue(Set(KarakasaSpriteArt.palette.values).isDisjoint(with: banned))
    }

    func testEveryFrameKeepsTheRedFrontFacingCyclopsAndSingleLeg() {
        for frame in KarakasaSpriteArt.allDefinitions {
            let canopy = points(in: frame, symbols: ["R", "r", "c", "h"], yRange: 6...37)
            XCTAssertGreaterThanOrEqual(canopy.count, 260, frame.name)
            if !canopy.isEmpty {
                let canopyBounds = bounds(of: canopy)
                XCTAssertLessThanOrEqual(abs(canopyBounds.doubledCenterX - 39), 2, frame.name)
                XCTAssertGreaterThanOrEqual(
                    Double(canopyBounds.height) / Double(canopyBounds.width),
                    0.75,
                    frame.name
                )
            }

            let eyeWhite = points(in: frame, symbols: ["w"], yRange: 11...19)
            let pupil = points(in: frame, symbols: ["k"], yRange: 12...18)
            XCTAssertEqual(componentCount(eyeWhite), 1, frame.name)
            XCTAssertFalse(pupil.isEmpty, frame.name)
            if !eyeWhite.isEmpty {
                XCTAssertLessThanOrEqual(abs(bounds(of: eyeWhite).doubledCenterX - 39), 2, frame.name)
            }

            let leg = points(in: frame, symbols: ["l"], yRange: 32...44)
            XCTAssertEqual(componentCount(leg), 1, frame.name)
            if !leg.isEmpty {
                XCTAssertLessThanOrEqual(abs(bounds(of: leg).doubledCenterX - 39), 2, frame.name)
            }

            let geta = points(in: frame, symbols: ["b", "B", "g"], yRange: 41...45)
            XCTAssertTrue(geta.contains { $0.y == 45 }, frame.name)
            XCTAssertFalse(frame.rows[46].contains { $0 != "." }, frame.name)
            XCTAssertFalse(frame.rows[47].contains { $0 != "." }, frame.name)
        }
    }

    func testKarakasaAnimationPreservesTheRegisteredIdleGeometry() {
        let canopySymbols: Set<Character> = ["R", "r", "c", "h"]
        let idlePoints = points(in: KarakasaSpriteArt.idle[0], symbols: canopySymbols)
        guard !idlePoints.isEmpty else {
            XCTFail(KarakasaSpriteArt.idle[0].name)
            return
        }
        let idle = bounds(of: idlePoints)

        for walk in KarakasaSpriteArt.walk {
            let currentPoints = points(in: walk, symbols: canopySymbols)
            guard !currentPoints.isEmpty else {
                XCTFail(walk.name)
                continue
            }
            let current = bounds(of: currentPoints)
            XCTAssertLessThanOrEqual(abs(current.doubledCenterX - idle.doubledCenterX), 2, walk.name)
            XCTAssertLessThanOrEqual(abs(current.width - idle.width), 2, walk.name)
            let getaPoints = points(in: walk, symbols: ["b", "B", "g"], yRange: 41...45)
            XCTAssertFalse(getaPoints.isEmpty, walk.name)
            if !getaPoints.isEmpty {
                let geta = bounds(of: getaPoints)
                XCTAssertLessThanOrEqual(abs(geta.doubledCenterX - 39), 4, walk.name)
            }
        }

        let hushPoints = points(in: KarakasaSpriteArt.hush[0], symbols: canopySymbols)
        XCTAssertFalse(hushPoints.isEmpty, KarakasaSpriteArt.hush[0].name)
        if !hushPoints.isEmpty {
            let hush = bounds(of: hushPoints)
            XCTAssertTrue((0...2).contains(hush.minY - idle.minY))
        }

        let anticipatePoints = points(in: KarakasaSpriteArt.strong[0], symbols: canopySymbols)
        XCTAssertFalse(anticipatePoints.isEmpty, KarakasaSpriteArt.strong[0].name)
        if !anticipatePoints.isEmpty {
            let anticipate = bounds(of: anticipatePoints)
            XCTAssertLessThanOrEqual(abs(anticipate.width - idle.width), 2)
        }

        let reactionPoints = points(in: KarakasaSpriteArt.strong[1], symbols: canopySymbols)
        XCTAssertFalse(reactionPoints.isEmpty, KarakasaSpriteArt.strong[1].name)
        if !reactionPoints.isEmpty {
            let reaction = bounds(of: reactionPoints)
            XCTAssertGreaterThanOrEqual(reaction.minX, idle.minX - 2)
            XCTAssertLessThanOrEqual(reaction.maxX, idle.maxX + 2)
            XCTAssertLessThanOrEqual(abs(reaction.doubledCenterX - idle.doubledCenterX), 2)
        }
    }
}
