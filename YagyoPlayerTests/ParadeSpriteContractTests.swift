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

private func opaquePoints(
    in definition: PixelSpriteDefinition,
    symbols: Set<Character>? = nil,
    yRange: ClosedRange<Int>? = nil
) -> Set<PixelPoint> {
    Set(definition.rows.enumerated().flatMap { y, row in
        row.enumerated().compactMap { x, symbol -> PixelPoint? in
            guard symbol != "." else { return nil }
            guard symbols?.contains(symbol) ?? true, yRange?.contains(y) ?? true else { return nil }
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

/// 残り行列妖怪の frame matrix 契約
/// (docs/superpowers/specs/2026-07-12-remaining-yokai-frame-matrix.md)。
private struct YokaiArtContract {
    let id: String
    let idle: [PixelSpriteDefinition]
    let walk: [PixelSpriteDefinition]
    let strong: [PixelSpriteDefinition]
    let allDefinitions: [PixelSpriteDefinition]
    let palette: [Character: UInt32]
    /// nil = 接地(全フレームで最下端が y = 45)。非nil = 浮遊体の最下端許容帯。
    let floatBand: ClosedRange<Int>?
    let widthRange: ClosedRange<Int>
    let heightRange: ClosedRange<Int>
    let anticipateSlack: Int
    let reactionGrowth: Int
    let reactionTopRise: Int

    init(
        id: String,
        idle: [PixelSpriteDefinition],
        walk: [PixelSpriteDefinition],
        strong: [PixelSpriteDefinition],
        allDefinitions: [PixelSpriteDefinition],
        palette: [Character: UInt32],
        floatBand: ClosedRange<Int>? = nil,
        widthRange: ClosedRange<Int>,
        heightRange: ClosedRange<Int>,
        anticipateSlack: Int = 2,
        reactionGrowth: Int = 3,
        reactionTopRise: Int = 4
    ) {
        self.id = id
        self.idle = idle
        self.walk = walk
        self.strong = strong
        self.allDefinitions = allDefinitions
        self.palette = palette
        self.floatBand = floatBand
        self.widthRange = widthRange
        self.heightRange = heightRange
        self.anticipateSlack = anticipateSlack
        self.reactionGrowth = reactionGrowth
        self.reactionTopRise = reactionTopRise
    }
}

private let contracts: [YokaiArtContract] = [
    YokaiArtContract(
        id: "oni",
        idle: OniSpriteArt.idle, walk: OniSpriteArt.walk, strong: OniSpriteArt.strong,
        allDefinitions: OniSpriteArt.allDefinitions, palette: OniSpriteArt.palette,
        widthRange: 20...32, heightRange: 26...38
    ),
    YokaiArtContract(
        id: "mokugyo",
        idle: MokugyoSpriteArt.idle, walk: MokugyoSpriteArt.walk, strong: MokugyoSpriteArt.strong,
        allDefinitions: MokugyoSpriteArt.allDefinitions, palette: MokugyoSpriteArt.palette,
        widthRange: 20...32, heightRange: 18...30, reactionTopRise: 6
    ),
    YokaiArtContract(
        id: "kappa",
        idle: KappaSpriteArt.idle, walk: KappaSpriteArt.walk, strong: KappaSpriteArt.strong,
        allDefinitions: KappaSpriteArt.allDefinitions, palette: KappaSpriteArt.palette,
        widthRange: 18...28, heightRange: 24...34
    ),
    YokaiArtContract(
        id: "kitsune",
        idle: KitsunebiSpriteArt.idle, walk: KitsunebiSpriteArt.walk, strong: KitsunebiSpriteArt.strong,
        allDefinitions: KitsunebiSpriteArt.allDefinitions, palette: KitsunebiSpriteArt.palette,
        floatBand: 40...44, widthRange: 16...26, heightRange: 24...34
    ),
    YokaiArtContract(
        id: "tengu",
        idle: TenguSpriteArt.idle, walk: TenguSpriteArt.walk, strong: TenguSpriteArt.strong,
        allDefinitions: TenguSpriteArt.allDefinitions, palette: TenguSpriteArt.palette,
        widthRange: 24...36, heightRange: 30...42, anticipateSlack: 3
    ),
    YokaiArtContract(
        id: "yuki",
        idle: YukiOnnaSpriteArt.idle, walk: YukiOnnaSpriteArt.walk, strong: YukiOnnaSpriteArt.strong,
        allDefinitions: YukiOnnaSpriteArt.allDefinitions, palette: YukiOnnaSpriteArt.palette,
        floatBand: 42...45, widthRange: 16...26, heightRange: 30...40
    ),
    YokaiArtContract(
        id: "biwa",
        idle: BiwaBokubokuSpriteArt.idle, walk: BiwaBokubokuSpriteArt.walk, strong: BiwaBokubokuSpriteArt.strong,
        allDefinitions: BiwaBokubokuSpriteArt.allDefinitions, palette: BiwaBokubokuSpriteArt.palette,
        widthRange: 18...30, heightRange: 28...38
    ),
    YokaiArtContract(
        id: "hitotsume",
        idle: HitotsumeSpriteArt.idle, walk: HitotsumeSpriteArt.walk, strong: HitotsumeSpriteArt.strong,
        allDefinitions: HitotsumeSpriteArt.allDefinitions, palette: HitotsumeSpriteArt.palette,
        widthRange: 14...24, heightRange: 20...30
    ),
]

final class ParadeSpriteContractTests: XCTestCase {
    private let strongCapableIDs: Set<String> = ["oni", "mokugyo", "kitsune", "tengu"]

    func testEveryYokaiKeepsItsFrameMatrix() {
        for contract in contracts {
            XCTAssertEqual(contract.idle.count, 1, contract.id)
            XCTAssertEqual(contract.walk.count, 4, contract.id)
            let expectedStrong = strongCapableIDs.contains(contract.id) ? 2 : 0
            XCTAssertEqual(contract.strong.count, expectedStrong, contract.id)

            let semanticOrder = contract.idle + contract.walk + contract.strong
            XCTAssertEqual(
                contract.allDefinitions.map(\.name),
                semanticOrder.map(\.name),
                contract.id
            )
        }
    }

    func testEveryFrameUsesTheSharedCanvasPaletteAndGroundAnchor() {
        for contract in contracts {
            for definition in contract.allDefinitions {
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
    }

    func testRenderedFramesStayFortyByFortyEight() {
        for contract in contracts {
            for frame in contract.allDefinitions.map({ PixelArt.frame($0) }) {
                XCTAssertEqual(frame.pixelWidth, 40, contract.id)
                XCTAssertEqual(frame.pixelHeight, 48, contract.id)
            }
        }
    }

    func testEveryPaletteSharesTheParadeInkAndBansLegacyPurple() {
        let banned: Set<UInt32> = [0x6e5aa8, 0x3f315f, 0x9f88d1, 0x2b203d]
        for contract in contracts {
            XCTAssertEqual(contract.palette["k"], 0x24160f, contract.id)
            XCTAssertTrue(
                Set(contract.palette.values).isDisjoint(with: banned),
                contract.id
            )
        }
    }

    func testGroundedYokaiTouchTheBaselineAndFloatersStayInTheirBand() {
        for contract in contracts {
            for definition in contract.allDefinitions {
                let lowest = definition.lowestOpaqueY
                if let band = contract.floatBand {
                    XCTAssertTrue(
                        band.contains(lowest),
                        "\(definition.name) floats outside \(band): lowest \(lowest)"
                    )
                } else {
                    XCTAssertEqual(lowest, 45, definition.name)
                }
            }
        }
    }

    func testEveryFrameStaysCenteredAndInsideItsSilhouetteBands() {
        for contract in contracts {
            for definition in contract.allDefinitions {
                let points = opaquePoints(in: definition)
                XCTAssertFalse(points.isEmpty, definition.name)
                guard !points.isEmpty else { continue }
                let box = bounds(of: points)
                XCTAssertLessThanOrEqual(abs(box.doubledCenterX - 39), 2, definition.name)
                XCTAssertTrue(
                    contract.widthRange.contains(box.width),
                    "\(definition.name) bbox width \(box.width) outside \(contract.widthRange)"
                )
                XCTAssertTrue(
                    contract.heightRange.contains(box.height),
                    "\(definition.name) bbox height \(box.height) outside \(contract.heightRange)"
                )
            }
        }
    }

    func testWalkFramesStayRegisteredToTheIdleGeometry() {
        for contract in contracts {
            guard let idleDefinition = contract.idle.first else {
                XCTFail(contract.id)
                continue
            }
            let idlePoints = opaquePoints(in: idleDefinition)
            guard !idlePoints.isEmpty else {
                XCTFail(idleDefinition.name)
                continue
            }
            let idle = bounds(of: idlePoints)

            for walk in contract.walk {
                let points = opaquePoints(in: walk)
                guard !points.isEmpty else {
                    XCTFail(walk.name)
                    continue
                }
                let current = bounds(of: points)
                XCTAssertLessThanOrEqual(
                    abs(current.doubledCenterX - idle.doubledCenterX), 2, walk.name
                )
                XCTAssertLessThanOrEqual(abs(current.width - idle.width), 4, walk.name)
                XCTAssertLessThanOrEqual(abs(current.minY - idle.minY), 3, walk.name)
            }
        }
    }

    func testStrongPairsStayAnticipationAndBoundedReaction() {
        for contract in contracts where !contract.strong.isEmpty {
            guard
                let idleDefinition = contract.idle.first,
                let anticipate = contract.strong.first,
                let reaction = contract.strong.dropFirst().first
            else {
                XCTFail(contract.id)
                continue
            }
            let idlePoints = opaquePoints(in: idleDefinition)
            let anticipatePoints = opaquePoints(in: anticipate)
            let reactionPoints = opaquePoints(in: reaction)
            guard !idlePoints.isEmpty, !anticipatePoints.isEmpty, !reactionPoints.isEmpty else {
                XCTFail(contract.id)
                continue
            }
            let idle = bounds(of: idlePoints)
            let anticipateBox = bounds(of: anticipatePoints)
            let reactionBox = bounds(of: reactionPoints)

            XCTAssertLessThanOrEqual(
                abs(anticipateBox.doubledCenterX - idle.doubledCenterX), 2, anticipate.name
            )
            XCTAssertTrue(
                (-1...contract.anticipateSlack).contains(anticipateBox.minX - idle.minX),
                anticipate.name
            )
            XCTAssertTrue(
                (-1...contract.anticipateSlack).contains(idle.maxX - anticipateBox.maxX),
                anticipate.name
            )

            XCTAssertLessThanOrEqual(
                abs(reactionBox.doubledCenterX - idle.doubledCenterX), 2, reaction.name
            )
            XCTAssertLessThanOrEqual(idle.minX - reactionBox.minX, contract.reactionGrowth, reaction.name)
            XCTAssertLessThanOrEqual(reactionBox.maxX - idle.maxX, contract.reactionGrowth, reaction.name)
            XCTAssertGreaterThanOrEqual(reactionBox.minX, 1, reaction.name)
            XCTAssertLessThanOrEqual(reactionBox.maxX, 38, reaction.name)
            XCTAssertLessThanOrEqual(idle.minY - reactionBox.minY, contract.reactionTopRise, reaction.name)
        }
    }
}
