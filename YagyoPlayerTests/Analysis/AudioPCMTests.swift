import AVFoundation
import XCTest
@testable import YagyoPlayer

final class AudioPCMTests: XCTestCase {
    func testMonoWithoutLayoutMapsToCenterRole() throws {
        let format = try PCMFixtureFactory.format(channelCount: 1, interleaved: false)

        let adapter = try AVAudioPCMBufferAdapter(format: format)

        XCTAssertEqual(adapter.sourceDescription, PCMSourceDescription(
            sampleRate: PCMFixtureFactory.sampleRate,
            channelCount: 1,
            channelRoles: [.center]
        ))
        XCTAssertEqual(adapter.analysisFormat?.channelRoles, [.center])
    }

    func testStereoWithoutLayoutMapsToLeftRightRoles() throws {
        let format = try PCMFixtureFactory.format(channelCount: 2, interleaved: true)

        let adapter = try AVAudioPCMBufferAdapter(format: format)

        XCTAssertEqual(adapter.sourceDescription.channelRoles, [.left, .right])
        XCTAssertEqual(adapter.analysisFormat?.channelRoles, [.left, .right])
    }

    func testSupportedTaggedLayoutsPreserveChannelRoleOrder() throws {
        let cases: [(AudioChannelLayoutTag, [AudioChannelRole])] = [
            (kAudioChannelLayoutTag_Mono, [.center]),
            (kAudioChannelLayoutTag_Stereo, [.left, .right]),
            (kAudioChannelLayoutTag_MPEG_3_0_A, [.left, .right, .center]),
            (kAudioChannelLayoutTag_MPEG_3_0_B, [.center, .left, .right]),
            (kAudioChannelLayoutTag_MPEG_4_0_A, [.left, .right, .center, .centerSurround]),
            (kAudioChannelLayoutTag_MPEG_4_0_B, [.center, .left, .right, .centerSurround]),
            (kAudioChannelLayoutTag_Quadraphonic, [.left, .right, .leftSurround, .rightSurround]),
            (kAudioChannelLayoutTag_ITU_2_2, [.left, .right, .leftSurround, .rightSurround]),
            (kAudioChannelLayoutTag_MPEG_5_0_A, [.left, .right, .center, .leftSurround, .rightSurround]),
            (kAudioChannelLayoutTag_MPEG_5_0_B, [.left, .right, .leftSurround, .rightSurround, .center]),
            (kAudioChannelLayoutTag_MPEG_5_0_C, [.left, .center, .right, .leftSurround, .rightSurround]),
            (kAudioChannelLayoutTag_MPEG_5_0_D, [.center, .left, .right, .leftSurround, .rightSurround]),
            (kAudioChannelLayoutTag_MPEG_5_1_A, [.left, .right, .center, .lfe, .leftSurround, .rightSurround]),
            (kAudioChannelLayoutTag_MPEG_5_1_B, [.left, .right, .leftSurround, .rightSurround, .center, .lfe]),
            (kAudioChannelLayoutTag_MPEG_5_1_C, [.left, .center, .right, .leftSurround, .rightSurround, .lfe]),
            (kAudioChannelLayoutTag_MPEG_5_1_D, [.center, .left, .right, .leftSurround, .rightSurround, .lfe]),
            (kAudioChannelLayoutTag_MPEG_7_1_A, [.left, .right, .center, .lfe, .leftSurround, .rightSurround, .leftCenter, .rightCenter]),
            (kAudioChannelLayoutTag_MPEG_7_1_B, [.center, .leftCenter, .rightCenter, .left, .right, .leftSurround, .rightSurround, .lfe]),
            (kAudioChannelLayoutTag_MPEG_7_1_C, [.left, .right, .center, .lfe, .leftSurround, .rightSurround, .rearSurroundLeft, .rearSurroundRight]),
            (kAudioChannelLayoutTag_AudioUnit_7_1, [.left, .right, .center, .lfe, .leftSurround, .rightSurround, .rearSurroundLeft, .rearSurroundRight])
        ]

        for (layoutTag, expectedRoles) in cases {
            let format = try PCMFixtureFactory.format(
                channelCount: AVAudioChannelCount(expectedRoles.count),
                layoutTag: layoutTag
            )
            let adapter = try AVAudioPCMBufferAdapter(format: format)

            XCTAssertEqual(adapter.sourceDescription.channelRoles, expectedRoles, "\(layoutTag)")
            XCTAssertEqual(adapter.analysisFormat?.channelRoles, expectedRoles, "\(layoutTag)")
            XCTAssertEqual(adapter.analysisFormat?.sampleRate, PCMFixtureFactory.sampleRate, "\(layoutTag)")
        }
    }

    func testAmbiguousUnlabelledMultichannelRejectsAnalysisButCopiesPCM() throws {
        let discreteThreeChannelLayout = kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(3)
        let format = try PCMFixtureFactory.format(
            channelCount: 3,
            interleaved: false,
            layoutTag: discreteThreeChannelLayout
        )
        let adapter = try AVAudioPCMBufferAdapter(format: format)
        let buffer = try PCMFixtureFactory.buffer(
            format: format,
            frameCount: 2,
            interleavedSamples: [1, 2, 3, 4, 5, 6]
        )
        var destination = Array(repeating: Float(0), count: 6)

        let copied = destination.withUnsafeMutableBufferPointer {
            adapter.copyInterleavedSamples(from: buffer, sourceFrameOffset: 0, frameCount: 2, into: $0)
        }

        XCTAssertNil(adapter.sourceDescription.channelRoles)
        XCTAssertNil(adapter.analysisFormat)
        XCTAssertTrue(copied)
        XCTAssertEqual(destination, [1, 2, 3, 4, 5, 6])
    }

    func testInterleavedFloat32OrderIsCopiedUnchanged() throws {
        let format = try PCMFixtureFactory.format(channelCount: 2, interleaved: true)
        let buffer = try PCMFixtureFactory.buffer(
            format: format,
            frameCount: 3,
            interleavedSamples: [1, 2, 3, 4, 5, 6]
        )
        let adapter = try AVAudioPCMBufferAdapter(format: format)
        var destination = Array(repeating: Float(0), count: 6)

        let copied = destination.withUnsafeMutableBufferPointer {
            adapter.copyInterleavedSamples(from: buffer, sourceFrameOffset: 0, frameCount: 3, into: $0)
        }

        XCTAssertTrue(copied)
        XCTAssertEqual(destination, [1, 2, 3, 4, 5, 6])
    }

    func testNoninterleavedFloat32IsInterleavedIntoCallerStorage() throws {
        let format = try PCMFixtureFactory.format(channelCount: 2, interleaved: false)
        let buffer = try PCMFixtureFactory.buffer(
            format: format,
            frameCount: 3,
            interleavedSamples: [1, 2, 3, 4, 5, 6]
        )
        let adapter = try AVAudioPCMBufferAdapter(format: format)
        var destination = Array(repeating: Float(0), count: 6)

        let copied = destination.withUnsafeMutableBufferPointer {
            adapter.copyInterleavedSamples(from: buffer, sourceFrameOffset: 0, frameCount: 3, into: $0)
        }

        XCTAssertTrue(copied)
        XCTAssertEqual(destination, [1, 2, 3, 4, 5, 6])
    }

    func testSelectedFrameRangeIsCopiedExactly() throws {
        let format = try PCMFixtureFactory.format(channelCount: 2, interleaved: true)
        let buffer = try PCMFixtureFactory.buffer(
            format: format,
            frameCount: 5,
            interleavedSamples: [10, 11, 20, 21, 30, 31, 40, 41, 50, 51]
        )
        let adapter = try AVAudioPCMBufferAdapter(format: format)
        var destination = Array(repeating: Float(0), count: 6)

        let copied = destination.withUnsafeMutableBufferPointer {
            adapter.copyInterleavedSamples(from: buffer, sourceFrameOffset: 1, frameCount: 3, into: $0)
        }

        XCTAssertTrue(copied)
        XCTAssertEqual(destination, [20, 21, 30, 31, 40, 41])
    }

    func testUndersizedDestinationRejectsWithoutPartialCopy() throws {
        let format = try PCMFixtureFactory.format(channelCount: 2, interleaved: true)
        let buffer = try PCMFixtureFactory.buffer(
            format: format,
            frameCount: 3,
            interleavedSamples: [1, 2, 3, 4, 5, 6]
        )
        let adapter = try AVAudioPCMBufferAdapter(format: format)
        var destination: [Float] = [99, 99, 99, 99, 99]

        let copied = destination.withUnsafeMutableBufferPointer {
            adapter.copyInterleavedSamples(from: buffer, sourceFrameOffset: 0, frameCount: 3, into: $0)
        }

        XCTAssertFalse(copied)
        XCTAssertEqual(destination, [99, 99, 99, 99, 99])
    }

    func testRepeatedCopiesReuseCallerOwnedStorageAddress() throws {
        let format = try PCMFixtureFactory.format(channelCount: 2, interleaved: false)
        let buffer = try PCMFixtureFactory.buffer(
            format: format,
            frameCount: 3,
            interleavedSamples: [1, 2, 3, 4, 5, 6]
        )
        let adapter = try AVAudioPCMBufferAdapter(format: format)
        var destination = Array(repeating: Float(0), count: 6)
        var addresses: [UInt] = []

        for _ in 0..<2 {
            let copied = destination.withUnsafeMutableBufferPointer { pointer -> Bool in
                addresses.append(UInt(bitPattern: pointer.baseAddress!))
                return adapter.copyInterleavedSamples(
                    from: buffer,
                    sourceFrameOffset: 0,
                    frameCount: 3,
                    into: pointer
                )
            }
            XCTAssertTrue(copied)
        }

        XCTAssertEqual(addresses.count, 2)
        XCTAssertEqual(addresses[0], addresses[1])
        XCTAssertEqual(destination, [1, 2, 3, 4, 5, 6])
    }
}
