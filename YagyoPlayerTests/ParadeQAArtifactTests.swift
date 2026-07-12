import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import YagyoPlayer

private enum ParadeQAError: LocalizedError {
    case emptyDefinitions
    case emptyRows(String)
    case invalidScale(Int)
    case invalidGap(Int)
    case inconsistentRowWidth(name: String, row: Int, expected: Int, actual: Int)
    case nonASCIIData(name: String, row: Int)
    case unknownSymbol(name: String, symbol: Character, x: Int, y: Int)
    case integerOverflow(String)
    case inconsistentCanvas(name: String, expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)
    case imageCreationFailed
    case destinationCreationFailed(String)
    case destinationFinalizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyDefinitions:
            return "At least one sprite definition is required."
        case let .emptyRows(name):
            return "\(name) has no pixel rows."
        case let .invalidScale(scale):
            return "Nearest-neighbor scale must be positive; received \(scale)."
        case let .invalidGap(gap):
            return "Contact-sheet gap must be nonnegative; received \(gap)."
        case let .inconsistentRowWidth(name, row, expected, actual):
            return "\(name) row \(row) is \(actual) pixels wide; expected \(expected)."
        case let .nonASCIIData(name, row):
            return "\(name) row \(row) contains non-ASCII pixel data."
        case let .unknownSymbol(name, symbol, x, y):
            return "\(name) contains unknown palette symbol '\(symbol)' at (\(x), \(y))."
        case let .integerOverflow(operation):
            return "Integer overflow while calculating \(operation)."
        case let .inconsistentCanvas(name, expectedWidth, expectedHeight, actualWidth, actualHeight):
            return "\(name) renders at \(actualWidth)x\(actualHeight); expected \(expectedWidth)x\(expectedHeight)."
        case .imageCreationFailed:
            return "Core Graphics could not create an RGBA image."
        case let .destinationCreationFailed(type):
            return "ImageIO could not create the \(type) destination."
        case let .destinationFinalizationFailed(type):
            return "ImageIO could not finalize the \(type) destination."
        }
    }
}

private struct ParadeRaster {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    func makeImage() throws -> CGImage {
        let bytesPerRow = try ParadeQARenderer.checkedMultiply(width, 4, context: "RGBA bytes per row")
        let expectedByteCount = try ParadeQARenderer.checkedMultiply(
            bytesPerRow,
            height,
            context: "RGBA image byte count"
        )
        guard
            rgba.count == expectedByteCount,
            let provider = CGDataProvider(data: Data(rgba) as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw ParadeQAError.imageCreationFailed
        }
        return image
    }
}

private enum ParadeQARenderer {
    struct MotionFrame {
        let definitionIndex: Int
        let duration: TimeInterval
    }

    /// 唐傘QAと同じ構造: idle → walk×2周 → (strong anticipate → reaction保持) → idle。
    static func motionTimeline(idleCount: Int, walkCount: Int, strongCount: Int) -> [MotionFrame] {
        var timeline = [MotionFrame(definitionIndex: 0, duration: 0.300)]
        for _ in 0..<2 {
            for offset in 0..<walkCount {
                timeline.append(MotionFrame(definitionIndex: idleCount + offset, duration: 0.125))
            }
        }
        if strongCount == 2 {
            let strongStart = idleCount + walkCount
            timeline.append(MotionFrame(definitionIndex: strongStart, duration: 0.070))
            timeline.append(MotionFrame(definitionIndex: strongStart + 1, duration: 0.270))
            timeline.append(MotionFrame(definitionIndex: strongStart + 1, duration: 0.270))
        }
        timeline.append(MotionFrame(definitionIndex: 0, duration: 0.300))
        return timeline
    }

    static func contactSheet(
        definitions: [PixelSpriteDefinition],
        scale: Int,
        gap: Int
    ) throws -> Data {
        guard !definitions.isEmpty else { throw ParadeQAError.emptyDefinitions }
        guard gap >= 0 else { throw ParadeQAError.invalidGap(gap) }

        let rasters = try definitions.map { try rasterize($0, scale: scale) }
        let expectedWidth = rasters[0].width
        let expectedHeight = rasters[0].height
        for (definition, raster) in zip(definitions, rasters) {
            guard raster.width == expectedWidth, raster.height == expectedHeight else {
                throw ParadeQAError.inconsistentCanvas(
                    name: definition.name,
                    expectedWidth: expectedWidth,
                    expectedHeight: expectedHeight,
                    actualWidth: raster.width,
                    actualHeight: raster.height
                )
            }
        }

        let framesWidth = try checkedMultiply(expectedWidth, rasters.count, context: "contact-sheet frame width")
        let gapsWidth = try checkedMultiply(gap, rasters.count - 1, context: "contact-sheet gap width")
        let sheetWidth = try checkedAdd(framesWidth, gapsWidth, context: "contact-sheet width")
        let pixelCount = try checkedMultiply(sheetWidth, expectedHeight, context: "contact-sheet pixel count")
        let byteCount = try checkedMultiply(pixelCount, 4, context: "contact-sheet byte count")
        var sheet = [UInt8](repeating: 0, count: byteCount)

        var destinationX = 0
        for raster in rasters {
            for y in 0..<raster.height {
                for x in 0..<raster.width {
                    let sourceOffset = (y * raster.width + x) * 4
                    let destinationOffset = (y * sheetWidth + destinationX + x) * 4
                    sheet[destinationOffset] = raster.rgba[sourceOffset]
                    sheet[destinationOffset + 1] = raster.rgba[sourceOffset + 1]
                    sheet[destinationOffset + 2] = raster.rgba[sourceOffset + 2]
                    sheet[destinationOffset + 3] = raster.rgba[sourceOffset + 3]
                }
            }
            destinationX += raster.width + gap
        }

        let image = try ParadeRaster(width: sheetWidth, height: expectedHeight, rgba: sheet).makeImage()
        return try encodePNG(image)
    }

    static func motionPreview(
        definitions: [PixelSpriteDefinition],
        timeline: [MotionFrame],
        scale: Int
    ) throws -> Data {
        guard !definitions.isEmpty else { throw ParadeQAError.emptyDefinitions }

        let rasters = try definitions.map { try rasterize($0, scale: scale) }
        let expectedWidth = rasters[0].width
        let expectedHeight = rasters[0].height
        for (definition, raster) in zip(definitions, rasters) {
            guard raster.width == expectedWidth, raster.height == expectedHeight else {
                throw ParadeQAError.inconsistentCanvas(
                    name: definition.name,
                    expectedWidth: expectedWidth,
                    expectedHeight: expectedHeight,
                    actualWidth: raster.width,
                    actualHeight: raster.height
                )
            }
        }
        let images = try rasters.map { try $0.makeImage() }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.gif.identifier as CFString,
            timeline.count,
            nil
        ) else {
            throw ParadeQAError.destinationCreationFailed("GIF")
        }

        let containerProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ] as [CFString: Any],
        ]
        CGImageDestinationSetProperties(destination, containerProperties as CFDictionary)

        for frame in timeline {
            guard images.indices.contains(frame.definitionIndex) else {
                throw ParadeQAError.emptyDefinitions
            }
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frame.duration,
                    kCGImagePropertyGIFUnclampedDelayTime: frame.duration,
                ] as [CFString: Any],
            ]
            CGImageDestinationAddImage(
                destination,
                images[frame.definitionIndex],
                frameProperties as CFDictionary
            )
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ParadeQAError.destinationFinalizationFailed("GIF")
        }
        return output as Data
    }

    fileprivate static func checkedMultiply(
        _ lhs: Int,
        _ rhs: Int,
        context: String
    ) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else { throw ParadeQAError.integerOverflow(context) }
        return result.partialValue
    }

    private static func checkedAdd(
        _ lhs: Int,
        _ rhs: Int,
        context: String
    ) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw ParadeQAError.integerOverflow(context) }
        return result.partialValue
    }

    private static func rasterize(
        _ definition: PixelSpriteDefinition,
        scale: Int
    ) throws -> ParadeRaster {
        guard scale > 0 else { throw ParadeQAError.invalidScale(scale) }
        guard let firstRow = definition.rows.first, !firstRow.isEmpty else {
            throw ParadeQAError.emptyRows(definition.name)
        }

        let logicalWidth = firstRow.utf8.count
        let logicalHeight = definition.rows.count
        for (y, row) in definition.rows.enumerated() {
            guard row.count == row.utf8.count else {
                throw ParadeQAError.nonASCIIData(name: definition.name, row: y)
            }
            guard row.utf8.count == logicalWidth else {
                throw ParadeQAError.inconsistentRowWidth(
                    name: definition.name,
                    row: y,
                    expected: logicalWidth,
                    actual: row.utf8.count
                )
            }
        }

        let width = try checkedMultiply(logicalWidth, scale, context: "scaled frame width")
        let height = try checkedMultiply(logicalHeight, scale, context: "scaled frame height")
        let pixelCount = try checkedMultiply(width, height, context: "scaled frame pixel count")
        let byteCount = try checkedMultiply(pixelCount, 4, context: "scaled frame byte count")
        var rgba = [UInt8](repeating: 0, count: byteCount)

        for (logicalY, row) in definition.rows.enumerated() {
            for (logicalX, symbol) in row.enumerated() {
                if symbol == "." { continue }
                guard let color = definition.palette[symbol] else {
                    throw ParadeQAError.unknownSymbol(
                        name: definition.name,
                        symbol: symbol,
                        x: logicalX,
                        y: logicalY
                    )
                }

                let red = UInt8((color >> 16) & 0xff)
                let green = UInt8((color >> 8) & 0xff)
                let blue = UInt8(color & 0xff)
                for offsetY in 0..<scale {
                    for offsetX in 0..<scale {
                        let x = logicalX * scale + offsetX
                        let y = logicalY * scale + offsetY
                        let offset = (y * width + x) * 4
                        rgba[offset] = red
                        rgba[offset + 1] = green
                        rgba[offset + 2] = blue
                        rgba[offset + 3] = 0xff
                    }
                }
            }
        }

        return ParadeRaster(width: width, height: height, rgba: rgba)
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ParadeQAError.destinationCreationFailed("PNG")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ParadeQAError.destinationFinalizationFailed("PNG")
        }
        return output as Data
    }
}

final class ParadeQAArtifactTests: XCTestCase {
    private struct Subject {
        let id: String
        let idle: [PixelSpriteDefinition]
        let walk: [PixelSpriteDefinition]
        let strong: [PixelSpriteDefinition]
        let allDefinitions: [PixelSpriteDefinition]
    }

    private let subjects: [Subject] = [
        Subject(
            id: "oni",
            idle: OniSpriteArt.idle, walk: OniSpriteArt.walk,
            strong: OniSpriteArt.strong, allDefinitions: OniSpriteArt.allDefinitions
        ),
        Subject(
            id: "mokugyo",
            idle: MokugyoSpriteArt.idle, walk: MokugyoSpriteArt.walk,
            strong: MokugyoSpriteArt.strong, allDefinitions: MokugyoSpriteArt.allDefinitions
        ),
        Subject(
            id: "kappa",
            idle: KappaSpriteArt.idle, walk: KappaSpriteArt.walk,
            strong: KappaSpriteArt.strong, allDefinitions: KappaSpriteArt.allDefinitions
        ),
        Subject(
            id: "kitsune",
            idle: KitsunebiSpriteArt.idle, walk: KitsunebiSpriteArt.walk,
            strong: KitsunebiSpriteArt.strong, allDefinitions: KitsunebiSpriteArt.allDefinitions
        ),
        Subject(
            id: "tengu",
            idle: TenguSpriteArt.idle, walk: TenguSpriteArt.walk,
            strong: TenguSpriteArt.strong, allDefinitions: TenguSpriteArt.allDefinitions
        ),
        Subject(
            id: "yuki",
            idle: YukiOnnaSpriteArt.idle, walk: YukiOnnaSpriteArt.walk,
            strong: YukiOnnaSpriteArt.strong, allDefinitions: YukiOnnaSpriteArt.allDefinitions
        ),
        Subject(
            id: "biwa",
            idle: BiwaBokubokuSpriteArt.idle, walk: BiwaBokubokuSpriteArt.walk,
            strong: BiwaBokubokuSpriteArt.strong, allDefinitions: BiwaBokubokuSpriteArt.allDefinitions
        ),
        Subject(
            id: "hitotsume",
            idle: HitotsumeSpriteArt.idle, walk: HitotsumeSpriteArt.walk,
            strong: HitotsumeSpriteArt.strong, allDefinitions: HitotsumeSpriteArt.allDefinitions
        ),
    ]

    func testExportsRemainingYokaiContactSheets() throws {
        for subject in subjects {
            assertSemanticOrder(subject)

            let data = try ParadeQARenderer.contactSheet(
                definitions: subject.allDefinitions,
                scale: 2,
                gap: 8
            )
            XCTAssertFalse(data.isEmpty, subject.id)

            let attachment = XCTAttachment(
                data: data,
                uniformTypeIdentifier: UTType.png.identifier
            )
            attachment.name = "\(subject.id)-contact-sheet.png"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testExportsRemainingYokaiMotionPreviews() throws {
        for subject in subjects {
            assertSemanticOrder(subject)

            let data = try ParadeQARenderer.motionPreview(
                definitions: subject.allDefinitions,
                timeline: ParadeQARenderer.motionTimeline(
                    idleCount: subject.idle.count,
                    walkCount: subject.walk.count,
                    strongCount: subject.strong.count
                ),
                scale: 2
            )
            XCTAssertFalse(data.isEmpty, subject.id)

            let attachment = XCTAttachment(
                data: data,
                uniformTypeIdentifier: UTType.gif.identifier
            )
            attachment.name = "\(subject.id)-motion-preview.gif"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func assertSemanticOrder(_ subject: Subject) {
        let semanticOrder = subject.idle + subject.walk + subject.strong
        XCTAssertEqual(
            subject.allDefinitions.map(\.name),
            semanticOrder.map(\.name),
            subject.id
        )
    }
}
