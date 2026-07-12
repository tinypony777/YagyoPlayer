import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import YagyoPlayer

private enum KarakasaQAError: LocalizedError {
    case emptyDefinitions
    case emptyRows(String)
    case invalidScale(Int)
    case invalidGap(Int)
    case inconsistentRowWidth(name: String, row: Int, expected: Int, actual: Int)
    case nonASCIIData(name: String, row: Int)
    case unknownSymbol(name: String, symbol: Character, x: Int, y: Int)
    case integerOverflow(String)
    case inconsistentCanvas(name: String, expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)
    case unexpectedDefinitionCount(expected: Int, actual: Int)
    case imageCreationFailed
    case destinationCreationFailed(String)
    case destinationFinalizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyDefinitions:
            return "At least one Karakasa definition is required."
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
        case let .unexpectedDefinitionCount(expected, actual):
            return "Karakasa QA rendering requires \(expected) semantic frames; received \(actual)."
        case .imageCreationFailed:
            return "Core Graphics could not create an RGBA image."
        case let .destinationCreationFailed(type):
            return "ImageIO could not create the \(type) destination."
        case let .destinationFinalizationFailed(type):
            return "ImageIO could not finalize the \(type) destination."
        }
    }
}

private struct KarakasaRaster {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    func makeImage() throws -> CGImage {
        let bytesPerRow = try KarakasaQARenderer.checkedMultiply(width, 4, context: "RGBA bytes per row")
        let expectedByteCount = try KarakasaQARenderer.checkedMultiply(
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
            throw KarakasaQAError.imageCreationFailed
        }
        return image
    }
}

private enum KarakasaQARenderer {
    private struct MotionFrame {
        let definitionIndex: Int
        let duration: TimeInterval
    }

    private static let motionTimeline: [MotionFrame] = [
        MotionFrame(definitionIndex: 0, duration: 0.300),
        MotionFrame(definitionIndex: 1, duration: 0.125),
        MotionFrame(definitionIndex: 2, duration: 0.125),
        MotionFrame(definitionIndex: 3, duration: 0.125),
        MotionFrame(definitionIndex: 4, duration: 0.125),
        MotionFrame(definitionIndex: 1, duration: 0.125),
        MotionFrame(definitionIndex: 2, duration: 0.125),
        MotionFrame(definitionIndex: 3, duration: 0.125),
        MotionFrame(definitionIndex: 4, duration: 0.125),
        MotionFrame(definitionIndex: 5, duration: 0.300),
        MotionFrame(definitionIndex: 5, duration: 0.300),
        MotionFrame(definitionIndex: 6, duration: 0.070),
        MotionFrame(definitionIndex: 7, duration: 0.270),
        MotionFrame(definitionIndex: 7, duration: 0.270),
        MotionFrame(definitionIndex: 0, duration: 0.300),
    ]

    static func contactSheet(
        definitions: [PixelSpriteDefinition],
        scale: Int,
        gap: Int
    ) throws -> Data {
        let expectedDefinitionCount = 8
        guard !definitions.isEmpty else { throw KarakasaQAError.emptyDefinitions }
        guard definitions.count == expectedDefinitionCount else {
            throw KarakasaQAError.unexpectedDefinitionCount(
                expected: expectedDefinitionCount,
                actual: definitions.count
            )
        }
        guard gap >= 0 else { throw KarakasaQAError.invalidGap(gap) }

        let rasters = try definitions.map { try rasterize($0, scale: scale) }
        let expectedWidth = rasters[0].width
        let expectedHeight = rasters[0].height
        for (definition, raster) in zip(definitions, rasters) {
            guard raster.width == expectedWidth, raster.height == expectedHeight else {
                throw KarakasaQAError.inconsistentCanvas(
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

        let image = try KarakasaRaster(width: sheetWidth, height: expectedHeight, rgba: sheet).makeImage()
        return try encodePNG(image)
    }

    static func motionPreview(
        definitions: [PixelSpriteDefinition],
        scale: Int
    ) throws -> Data {
        let expectedDefinitionCount = 8
        guard definitions.count == expectedDefinitionCount else {
            throw KarakasaQAError.unexpectedDefinitionCount(
                expected: expectedDefinitionCount,
                actual: definitions.count
            )
        }

        let rasters = try definitions.map { try rasterize($0, scale: scale) }
        let expectedWidth = rasters[0].width
        let expectedHeight = rasters[0].height
        for (definition, raster) in zip(definitions, rasters) {
            guard raster.width == expectedWidth, raster.height == expectedHeight else {
                throw KarakasaQAError.inconsistentCanvas(
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
            motionTimeline.count,
            nil
        ) else {
            throw KarakasaQAError.destinationCreationFailed("GIF")
        }

        let containerProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ] as [CFString: Any],
        ]
        CGImageDestinationSetProperties(destination, containerProperties as CFDictionary)

        for frame in motionTimeline {
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
            throw KarakasaQAError.destinationFinalizationFailed("GIF")
        }
        return output as Data
    }

    fileprivate static func checkedMultiply(
        _ lhs: Int,
        _ rhs: Int,
        context: String
    ) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else { throw KarakasaQAError.integerOverflow(context) }
        return result.partialValue
    }

    private static func checkedAdd(
        _ lhs: Int,
        _ rhs: Int,
        context: String
    ) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw KarakasaQAError.integerOverflow(context) }
        return result.partialValue
    }

    private static func rasterize(
        _ definition: PixelSpriteDefinition,
        scale: Int
    ) throws -> KarakasaRaster {
        guard scale > 0 else { throw KarakasaQAError.invalidScale(scale) }
        guard let firstRow = definition.rows.first, !firstRow.isEmpty else {
            throw KarakasaQAError.emptyRows(definition.name)
        }

        let logicalWidth = firstRow.utf8.count
        let logicalHeight = definition.rows.count
        for (y, row) in definition.rows.enumerated() {
            guard row.count == row.utf8.count else {
                throw KarakasaQAError.nonASCIIData(name: definition.name, row: y)
            }
            guard row.utf8.count == logicalWidth else {
                throw KarakasaQAError.inconsistentRowWidth(
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
                    throw KarakasaQAError.unknownSymbol(
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

        return KarakasaRaster(width: width, height: height, rgba: rgba)
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw KarakasaQAError.destinationCreationFailed("PNG")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw KarakasaQAError.destinationFinalizationFailed("PNG")
        }
        return output as Data
    }
}

final class KarakasaQAArtifactTests: XCTestCase {
    func testExportsReferenceFaithfulKarakasaContactSheet() throws {
        let definitions = KarakasaSpriteArt.allDefinitions
        assertSemanticOrder(definitions)

        let data = try KarakasaQARenderer.contactSheet(
            definitions: definitions,
            scale: 2,
            gap: 8
        )
        XCTAssertFalse(data.isEmpty)

        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: UTType.png.identifier
        )
        attachment.name = "karakasa-contact-sheet.png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testExportsReferenceFaithfulKarakasaMotionPreview() throws {
        let definitions = KarakasaSpriteArt.allDefinitions
        assertSemanticOrder(definitions)

        let data = try KarakasaQARenderer.motionPreview(
            definitions: definitions,
            scale: 2
        )
        XCTAssertFalse(data.isEmpty)

        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: UTType.gif.identifier
        )
        attachment.name = "karakasa-motion-preview.gif"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertSemanticOrder(_ definitions: [PixelSpriteDefinition]) {
        let semanticOrder = KarakasaSpriteArt.idle
            + KarakasaSpriteArt.walk
            + KarakasaSpriteArt.hush
            + KarakasaSpriteArt.strong
        XCTAssertEqual(definitions.map(\.name), semanticOrder.map(\.name))
    }
}
