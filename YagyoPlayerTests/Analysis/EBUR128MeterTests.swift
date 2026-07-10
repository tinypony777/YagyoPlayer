import XCTest
@testable import YagyoPlayer

final class EBUR128MeterTests: XCTestCase {
    private let expectedMonoIntegrated = -23.003598632937894
    private let expectedDualIntegrated = -19.99329867629808
    private let expectedMonoMomentary = -23.00359554324374
    private let expectedMonoShortTerm = -23.003595543243016

    func testTenSecondMonoSineProducesReferenceIntegratedMomentaryAndShortTerm() throws {
        let format = try AnalysisPCMFormat(sampleRate: PCMFixtureFactory.sampleRate, channelRoles: [.center])
        let samples = PCMFixtureFactory.sine(format: format)
        let meter = try meter(format: format, samples: samples, chunkSize: 1_024)

        let integrated = try finiteValue(meter.integrated())
        let momentary = try finiteValue(meter.momentary())
        let shortTerm = try finiteValue(meter.shortTerm())

        XCTAssertEqual(integrated, expectedMonoIntegrated, accuracy: 0.01)
        XCTAssertEqual(momentary, expectedMonoMomentary, accuracy: 0.01)
        XCTAssertEqual(shortTerm, expectedMonoShortTerm, accuracy: 0.01)
    }

    func testTenSecondDualChannelSineProducesReferenceIntegrated() throws {
        let format = try AnalysisPCMFormat(sampleRate: PCMFixtureFactory.sampleRate, channelRoles: [.left, .right])
        let samples = PCMFixtureFactory.sine(format: format)
        let meter = try meter(format: format, samples: samples, chunkSize: 1_024)

        XCTAssertEqual(try finiteValue(meter.integrated()), expectedDualIntegrated, accuracy: 0.01)
    }

    func testOneSidedStereoIntegratedMatchesMonoReference() throws {
        let format = try AnalysisPCMFormat(sampleRate: PCMFixtureFactory.sampleRate, channelRoles: [.left, .right])
        let samples = PCMFixtureFactory.sine(format: format, activeChannels: [0])
        let meter = try meter(format: format, samples: samples, chunkSize: 1_024)

        XCTAssertEqual(try finiteValue(meter.integrated()), expectedMonoIntegrated, accuracy: 0.01)
    }

    func testMomentaryIsUnavailableBeforeFourHundredMilliseconds() throws {
        let format = try AnalysisPCMFormat(sampleRate: PCMFixtureFactory.sampleRate, channelRoles: [.center])
        let samples = PCMFixtureFactory.sine(format: format, duration: 0.399)
        let meter = try meter(format: format, samples: samples, chunkSize: 257)

        XCTAssertEqual(try meter.momentary(), .unavailable)
    }

    func testShortTermIsUnavailableBeforeThreeSeconds() throws {
        let format = try AnalysisPCMFormat(sampleRate: PCMFixtureFactory.sampleRate, channelRoles: [.center])
        let samples = PCMFixtureFactory.sine(format: format, duration: 2.999)
        let meter = try meter(format: format, samples: samples, chunkSize: 257)

        XCTAssertEqual(try meter.shortTerm(), .unavailable)
    }

    func testLFESamplesDoNotChangeLoudness() throws {
        let format = try AnalysisPCMFormat(sampleRate: PCMFixtureFactory.sampleRate, channelRoles: [.left, .lfe])
        let leftOnly = PCMFixtureFactory.sine(format: format, activeChannels: [0])
        let leftAndLFE = PCMFixtureFactory.sine(format: format, activeChannels: [0, 1])

        let leftOnlyValue = try finiteValue(meter(format: format, samples: leftOnly, chunkSize: 1_024).integrated())
        let leftAndLFEValue = try finiteValue(meter(format: format, samples: leftAndLFE, chunkSize: 1_024).integrated())

        XCTAssertEqual(leftOnlyValue, leftAndLFEValue, accuracy: 1e-9)
    }

    func testAllZeroResultIsNegativeInfinityWithNilExternalValue() throws {
        let format = try AnalysisPCMFormat(sampleRate: PCMFixtureFactory.sampleRate, channelRoles: [.center])
        let frameCount = Int(format.sampleRate * 10)
        let samples = Array(repeating: Float(0), count: frameCount * format.channelCount)
        let reading = try meter(format: format, samples: samples, chunkSize: 4_096).integrated()

        XCTAssertEqual(reading, .negativeInfinity)
        XCTAssertNil(reading.externalValue)
    }

    func testChunkSizesProduceIdenticalLoudnessReadings() throws {
        let format = try AnalysisPCMFormat(sampleRate: PCMFixtureFactory.sampleRate, channelRoles: [.center])
        let samples = PCMFixtureFactory.sine(format: format)
        let values = try [64, 257, 1_024, 4_096].map { chunkSize in
            let meter = try meter(format: format, samples: samples, chunkSize: chunkSize)
            return (
                integrated: try finiteValue(meter.integrated()),
                momentary: try finiteValue(meter.momentary()),
                shortTerm: try finiteValue(meter.shortTerm())
            )
        }

        assertValuesWithinOneBillionth(values.map { $0.integrated })
        assertValuesWithinOneBillionth(values.map { $0.momentary })
        assertValuesWithinOneBillionth(values.map { $0.shortTerm })
    }

    func testEveryRoleMapsToExpectedIsolatedChannelGain() throws {
        let surroundGain = 10 * log10(1.41)
        let baseRoles: [AudioChannelRole] = [
            .left, .right, .center, .leftCenter, .rightCenter,
            .rearSurroundLeft, .rearSurroundRight, .centerSurround
        ]
        let boostedRoles: [AudioChannelRole] = [
            .leftSurround, .rightSurround, .leftSurroundDirect, .rightSurroundDirect
        ]

        for role in baseRoles {
            let value = try isolatedIntegratedLoudness(for: role)
            XCTAssertEqual(value, expectedMonoIntegrated, accuracy: 0.01, "\(role)")
        }
        for role in boostedRoles {
            let value = try isolatedIntegratedLoudness(for: role)
            XCTAssertEqual(value, expectedMonoIntegrated + surroundGain, accuracy: 0.01, "\(role)")
        }

        let lfeReading = try isolatedIntegratedReading(for: .lfe)
        XCTAssertEqual(lfeReading, .negativeInfinity)
        XCTAssertNil(lfeReading.externalValue)
    }

    func testMPEGAndQuadFourPointZeroLayoutsUseDistinctSurroundRoles() throws {
        let mpeg = try AnalysisPCMFormat(
            sampleRate: PCMFixtureFactory.sampleRate,
            channelRoles: [.left, .right, .center, .centerSurround]
        )
        let quad = try AnalysisPCMFormat(
            sampleRate: PCMFixtureFactory.sampleRate,
            channelRoles: [.left, .right, .leftSurround, .rightSurround]
        )
        let surroundGain = 10 * log10(1.41)

        XCTAssertEqual(try isolatedIntegratedLoudness(format: mpeg, channel: 2), expectedMonoIntegrated, accuracy: 0.01)
        XCTAssertEqual(try isolatedIntegratedLoudness(format: mpeg, channel: 3), expectedMonoIntegrated, accuracy: 0.01)
        XCTAssertEqual(try isolatedIntegratedLoudness(format: quad, channel: 2), expectedMonoIntegrated + surroundGain, accuracy: 0.01)
        XCTAssertEqual(try isolatedIntegratedLoudness(format: quad, channel: 3), expectedMonoIntegrated + surroundGain, accuracy: 0.01)
    }

    func testAcceptedSevenPointOneVariantsPreserveFrontCenterAndRearRoleGains() throws {
        let frontCenterVariant = try AnalysisPCMFormat(
            sampleRate: PCMFixtureFactory.sampleRate,
            channelRoles: [.left, .right, .center, .lfe, .leftSurround, .rightSurround, .leftCenter, .rightCenter]
        )
        let rearVariant = try AnalysisPCMFormat(
            sampleRate: PCMFixtureFactory.sampleRate,
            channelRoles: [.left, .right, .center, .lfe, .leftSurround, .rightSurround, .rearSurroundLeft, .rearSurroundRight]
        )
        let surroundGain = 10 * log10(1.41)

        XCTAssertEqual(try isolatedIntegratedLoudness(format: frontCenterVariant, channel: 4), expectedMonoIntegrated + surroundGain, accuracy: 0.01)
        XCTAssertEqual(try isolatedIntegratedLoudness(format: frontCenterVariant, channel: 6), expectedMonoIntegrated, accuracy: 0.01)
        XCTAssertEqual(try isolatedIntegratedLoudness(format: rearVariant, channel: 4), expectedMonoIntegrated + surroundGain, accuracy: 0.01)
        XCTAssertEqual(try isolatedIntegratedLoudness(format: rearVariant, channel: 6), expectedMonoIntegrated, accuracy: 0.01)
    }

    private func isolatedIntegratedLoudness(for role: AudioChannelRole) throws -> Double {
        try finiteValue(isolatedIntegratedReading(for: role))
    }

    private func isolatedIntegratedReading(for role: AudioChannelRole) throws -> LoudnessReading {
        let format = try AnalysisPCMFormat(sampleRate: PCMFixtureFactory.sampleRate, channelRoles: [role])
        let samples = PCMFixtureFactory.sine(format: format)
        return try meter(format: format, samples: samples, chunkSize: 1_024).integrated()
    }

    private func isolatedIntegratedLoudness(format: AnalysisPCMFormat, channel: Int) throws -> Double {
        let samples = PCMFixtureFactory.sine(format: format, activeChannels: [channel])
        return try finiteValue(meter(format: format, samples: samples, chunkSize: 1_024).integrated())
    }

    private func meter(format: AnalysisPCMFormat, samples: [Float], chunkSize: Int) throws -> EBUR128Meter {
        let meter = try EBUR128Meter(format: format)
        let frameCount = samples.count / format.channelCount
        try samples.withUnsafeBufferPointer { samplesPointer in
            var frameOffset = 0
            while frameOffset < frameCount {
                let framesToCopy = min(chunkSize, frameCount - frameOffset)
                let sampleOffset = frameOffset * format.channelCount
                let chunk = UnsafeBufferPointer(
                    start: samplesPointer.baseAddress!.advanced(by: sampleOffset),
                    count: framesToCopy * format.channelCount
                )
                try meter.addFrames(chunk, frameCount: framesToCopy)
                frameOffset += framesToCopy
            }
        }
        return meter
    }

    private func finiteValue(_ reading: LoudnessReading) throws -> Double {
        guard case .finite(let value) = reading else {
            XCTFail("Expected finite loudness, got \(reading)")
            throw TestFailure.unexpectedReading
        }
        return value
    }

    private func assertValuesWithinOneBillionth(
        _ values: [Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual((values.max() ?? 0) - (values.min() ?? 0), 1e-9, file: file, line: line)
    }

    private enum TestFailure: Error {
        case unexpectedReading
    }
}
