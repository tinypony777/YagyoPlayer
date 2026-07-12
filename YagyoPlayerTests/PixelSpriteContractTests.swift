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

    func strictlyContains(_ point: PixelPoint) -> Bool {
        point.x > minX && point.x < maxX && point.y > minY && point.y < maxY
    }
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

private func connectedComponents(_ source: Set<PixelPoint>) -> [Set<PixelPoint>] {
    var remaining = source
    var components: [Set<PixelPoint>] = []
    while let start = remaining.first {
        var stack = [start]
        var component: Set<PixelPoint> = [start]
        remaining.remove(start)
        while let point = stack.popLast() {
            let neighbors = [
                PixelPoint(x: point.x - 1, y: point.y),
                PixelPoint(x: point.x + 1, y: point.y),
                PixelPoint(x: point.x, y: point.y - 1),
                PixelPoint(x: point.x, y: point.y + 1),
            ]
            for neighbor in neighbors where remaining.remove(neighbor) != nil {
                component.insert(neighbor)
                stack.append(neighbor)
            }
        }
        components.append(component)
    }
    return components
}

private func componentCount(_ source: Set<PixelPoint>) -> Int {
    connectedComponents(source).count
}

private func areOrthogonallyAdjacent(
    _ lhs: Set<PixelPoint>,
    _ rhs: Set<PixelPoint>
) -> Bool {
    lhs.contains { point in
        let neighbors = [
            PixelPoint(x: point.x - 1, y: point.y),
            PixelPoint(x: point.x + 1, y: point.y),
            PixelPoint(x: point.x, y: point.y - 1),
            PixelPoint(x: point.x, y: point.y + 1),
        ]
        return neighbors.contains { rhs.contains($0) }
    }
}

private func horizontalRunCount(in points: Set<PixelPoint>, y: Int) -> Int {
    let xs = points.lazy.filter { $0.y == y }.map(\.x).sorted()
    var previousX: Int?
    var count = 0
    for x in xs {
        if previousX.map({ x > $0 + 1 }) ?? true {
            count += 1
        }
        previousX = x
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
        let approved: [Character: UInt32] = [
            "k": 0x24160f,
            "R": 0x8e2f2d, "r": 0xc94545, "c": 0xe45c5e, "h": 0xf37a76,
            "w": 0xfff3da,
            "p": 0xf18da6, "P": 0xc85f7e,
            "l": 0xf5d7c5,
            "b": 0x80512f, "B": 0x4a2e1f, "g": 0xd5a32c,
        ]
        let banned: Set<UInt32> = [0x6e5aa8, 0x3f315f, 0x9f88d1, 0x2b203d]
        XCTAssertEqual(KarakasaSpriteArt.palette, approved)
        XCTAssertTrue(Set(KarakasaSpriteArt.palette.values).isDisjoint(with: banned))
    }

    func testEveryFrameKeepsADominantSymmetricRedCone() {
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

                let thirdHeight = max(canopyBounds.height / 3, 1)
                let upper = Set(canopy.filter { $0.y < canopyBounds.minY + thirdHeight })
                let lower = Set(canopy.filter { $0.y > canopyBounds.maxY - thirdHeight })
                if !upper.isEmpty && !lower.isEmpty {
                    let upperBounds = bounds(of: upper)
                    let lowerBounds = bounds(of: lower)
                    XCTAssertLessThan(lowerBounds.minX, upperBounds.minX, frame.name)
                    XCTAssertGreaterThan(lowerBounds.maxX, upperBounds.maxX, frame.name)
                    XCTAssertGreaterThan(lowerBounds.width, upperBounds.width, frame.name)
                } else {
                    XCTFail(frame.name)
                }

                let pointsByRow = Dictionary(grouping: canopy, by: { $0.y })
                for (y, rowPoints) in pointsByRow {
                    let rowBounds = bounds(of: Set(rowPoints))
                    XCTAssertLessThanOrEqual(
                        abs(rowBounds.doubledCenterX - 39),
                        2,
                        "\(frame.name) y=\(y)"
                    )
                }
            }

            let dominanceCanopy = points(
                in: frame,
                symbols: ["R", "r", "c", "h"],
                yRange: 6...35
            )
            let nonOutlineSymbols = frame.usedSymbols.subtracting(["k"])
            let nonOutlineOpaque = points(
                in: frame,
                symbols: nonOutlineSymbols,
                yRange: 6...35
            )
            let otherOpaque = nonOutlineOpaque.subtracting(dominanceCanopy)
            XCTAssertGreaterThan(dominanceCanopy.count, otherOpaque.count, frame.name)
            if !nonOutlineOpaque.isEmpty {
                XCTAssertGreaterThanOrEqual(
                    Double(dominanceCanopy.count) / Double(nonOutlineOpaque.count),
                    0.55,
                    frame.name
                )
            }
        }
    }

    func testEveryFrameKeepsOneContainedPupil() {
        for frame in KarakasaSpriteArt.allDefinitions {
            let eyeWhite = points(in: frame, symbols: ["w"], yRange: 11...19)
            XCTAssertEqual(componentCount(eyeWhite), 1, frame.name)
            guard !eyeWhite.isEmpty else { continue }

            let eyeBounds = bounds(of: eyeWhite)
            XCTAssertLessThanOrEqual(abs(eyeBounds.doubledCenterX - 39), 2, frame.name)

            let darkPoints = points(in: frame, symbols: ["k"])
            let pupilComponents = connectedComponents(darkPoints).filter { component in
                component.allSatisfy { eyeBounds.strictlyContains($0) }
            }
            XCTAssertEqual(pupilComponents.count, 1, frame.name)
            guard pupilComponents.count == 1, let pupil = pupilComponents.first else { continue }

            let pupilBounds = bounds(of: pupil)
            XCTAssertEqual(componentCount(pupil), 1, frame.name)
            XCTAssertGreaterThan(darkPoints.count, pupil.count, frame.name)
            XCTAssertLessThanOrEqual(
                abs(pupilBounds.doubledCenterX - eyeBounds.doubledCenterX),
                2,
                frame.name
            )
            XCTAssertTrue(areOrthogonallyAdjacent(pupil, eyeWhite), frame.name)
        }
    }

    func testEveryFrameKeepsCenteredMouthAndTongue() {
        for frame in KarakasaSpriteArt.allDefinitions {
            let mouth = Set(
                points(in: frame, symbols: ["k"], yRange: 18...21)
                    .filter { (14...25).contains($0.x) }
            )
            XCTAssertFalse(mouth.isEmpty, frame.name)
            if !mouth.isEmpty {
                XCTAssertLessThanOrEqual(abs(bounds(of: mouth).doubledCenterX - 39), 2, frame.name)
            }

            let tongue = points(in: frame, symbols: ["p", "P"], yRange: 20...27)
            XCTAssertFalse(tongue.isEmpty, frame.name)
            if !tongue.isEmpty {
                XCTAssertLessThanOrEqual(abs(bounds(of: tongue).doubledCenterX - 39), 2, frame.name)
            }
        }
    }

    func testEveryFrameKeepsOneConnectedLegAndGeta() {
        for frame in KarakasaSpriteArt.allDefinitions {
            let leg = points(in: frame, symbols: ["l"], yRange: 32...44)
            let geta = points(in: frame, symbols: ["b", "B", "g"], yRange: 41...45)

            XCTAssertEqual(componentCount(leg), 1, frame.name)
            XCTAssertEqual(componentCount(geta), 1, frame.name)
            XCTAssertTrue(geta.contains { $0.y == 45 }, frame.name)
            XCTAssertFalse(
                frame.rows.enumerated().contains { y, row in
                    y > 45 && row.contains { $0 != "." }
                },
                frame.name
            )

            guard !leg.isEmpty, !geta.isEmpty else { continue }

            let legBounds = bounds(of: leg)
            let getaBounds = bounds(of: geta)
            XCTAssertGreaterThanOrEqual(legBounds.height, 7, frame.name)
            XCTAssertLessThanOrEqual(legBounds.width, 4, frame.name)
            XCTAssertLessThanOrEqual(abs(legBounds.doubledCenterX - 39), 2, frame.name)
            for y in legBounds.minY...legBounds.maxY {
                XCTAssertEqual(horizontalRunCount(in: leg, y: y), 1, "\(frame.name) y=\(y)")
            }

            XCTAssertGreaterThan(getaBounds.width, legBounds.width, frame.name)
            XCTAssertGreaterThan(getaBounds.width, getaBounds.height, frame.name)
            XCTAssertGreaterThanOrEqual(getaBounds.height, 2, frame.name)
            let isWalkFrame = KarakasaSpriteArt.walk.contains { $0.name == frame.name }
            let getaCenterTolerance = isWalkFrame ? 4 : 2
            XCTAssertLessThanOrEqual(
                abs(getaBounds.doubledCenterX - 39),
                getaCenterTolerance,
                frame.name
            )
            XCTAssertEqual(getaBounds.maxY, 45, frame.name)
            XCTAssertTrue(areOrthogonallyAdjacent(leg, geta), frame.name)
            XCTAssertEqual(componentCount(leg.union(geta)), 1, frame.name)
        }
    }

    func testKarakasaAnimationPreservesTheRegisteredIdleGeometry() {
        let canopySymbols: Set<Character> = ["R", "r", "c", "h"]
        guard let idleFrame = KarakasaSpriteArt.idle.first else {
            XCTFail("Missing idle frame")
            return
        }
        guard let hushFrame = KarakasaSpriteArt.hush.first else {
            XCTFail("Missing hush frame")
            return
        }
        guard let anticipateFrame = KarakasaSpriteArt.strong.first else {
            XCTFail("Missing strong anticipate frame")
            return
        }
        guard let reactionFrame = KarakasaSpriteArt.strong.dropFirst().first else {
            XCTFail("Missing strong reaction frame")
            return
        }

        let idlePoints = points(
            in: idleFrame,
            symbols: canopySymbols,
            yRange: 6...37
        )
        guard !idlePoints.isEmpty else {
            XCTFail(idleFrame.name)
            return
        }
        let idle = bounds(of: idlePoints)

        for walk in KarakasaSpriteArt.walk {
            let currentPoints = points(in: walk, symbols: canopySymbols, yRange: 6...37)
            guard !currentPoints.isEmpty else {
                XCTFail(walk.name)
                continue
            }
            let current = bounds(of: currentPoints)
            XCTAssertLessThanOrEqual(abs(current.doubledCenterX - idle.doubledCenterX), 2, walk.name)
            XCTAssertLessThanOrEqual(abs(current.width - idle.width), 2, walk.name)
            XCTAssertLessThanOrEqual(abs(current.minY - idle.minY), 2, walk.name)
            let getaPoints = points(in: walk, symbols: ["b", "B", "g"], yRange: 41...45)
            XCTAssertFalse(getaPoints.isEmpty, walk.name)
            if !getaPoints.isEmpty {
                let geta = bounds(of: getaPoints)
                XCTAssertLessThanOrEqual(abs(geta.doubledCenterX - 39), 4, walk.name)
            }
        }

        let hushPoints = points(in: hushFrame, symbols: canopySymbols, yRange: 6...37)
        XCTAssertFalse(hushPoints.isEmpty, hushFrame.name)
        if !hushPoints.isEmpty {
            let hush = bounds(of: hushPoints)
            XCTAssertTrue((0...2).contains(hush.minY - idle.minY))
            XCTAssertTrue((0...2).contains(hush.maxY - idle.maxY))
            XCTAssertLessThanOrEqual(abs(hush.doubledCenterX - idle.doubledCenterX), 2)
            XCTAssertLessThanOrEqual(abs(hush.width - idle.width), 2)
        }

        let anticipatePoints = points(
            in: anticipateFrame,
            symbols: canopySymbols,
            yRange: 6...37
        )
        XCTAssertFalse(anticipatePoints.isEmpty, anticipateFrame.name)
        if !anticipatePoints.isEmpty {
            let anticipate = bounds(of: anticipatePoints)
            XCTAssertTrue((0...1).contains(anticipate.minX - idle.minX))
            XCTAssertTrue((0...1).contains(idle.maxX - anticipate.maxX))
            XCTAssertTrue((0...1).contains(anticipate.minY - idle.minY))
            XCTAssertTrue((0...1).contains(idle.maxY - anticipate.maxY))
            XCTAssertTrue((1...2).contains(idle.width - anticipate.width))
            XCTAssertTrue((1...2).contains(idle.height - anticipate.height))
            XCTAssertLessThanOrEqual(abs(anticipate.doubledCenterX - idle.doubledCenterX), 2)
        }

        let reactionPoints = points(
            in: reactionFrame,
            symbols: canopySymbols,
            yRange: 6...37
        )
        XCTAssertFalse(reactionPoints.isEmpty, reactionFrame.name)
        if !reactionPoints.isEmpty {
            let reaction = bounds(of: reactionPoints)
            XCTAssertTrue((0...2).contains(idle.minX - reaction.minX))
            XCTAssertTrue((0...2).contains(reaction.maxX - idle.maxX))
            XCTAssertTrue((1...4).contains(reaction.width - idle.width))
            XCTAssertLessThanOrEqual(abs(reaction.minY - idle.minY), 2)
            XCTAssertLessThanOrEqual(abs(reaction.maxY - idle.maxY), 2)
            XCTAssertLessThanOrEqual(abs(reaction.doubledCenterX - idle.doubledCenterX), 2)
        }
    }
}
