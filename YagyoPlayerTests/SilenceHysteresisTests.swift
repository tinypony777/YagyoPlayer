import XCTest

@testable import YagyoPlayer

final class SilenceHysteresisTests: XCTestCase {
    func testCodableNormalizesNonFiniteFiniteCaseToUnavailable() throws {
        let legacyData = Data(#"{"finite":{"_0":-18.2}}"#.utf8)

        XCTAssertEqual(
            try JSONDecoder().decode(LoudnessReading.self, from: legacyData),
            .finite(-18.2)
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                LoudnessReading.self,
                from: JSONEncoder().encode(LoudnessReading.finite(-18.2))
            ),
            .finite(-18.2)
        )

        let data = try JSONEncoder().encode(LoudnessReading.finite(.nan))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("NaN"))
        XCTAssertFalse(json.contains("Infinity"))
        XCTAssertEqual(
            try JSONDecoder().decode(LoudnessReading.self, from: data),
            .unavailable
        )
    }

    func testEntryAndExitThresholdsKeepFiveLUHysteresis() {
        var detector = SilenceHysteresis()

        XCTAssertFalse(detector.observe(.finite(-69.999)))
        XCTAssertTrue(detector.observe(.finite(-70.0)))
        XCTAssertTrue(detector.observe(.finite(-65.0)))
        XCTAssertFalse(detector.observe(.finite(-64.999)))

        XCTAssertEqual(detector.summary.observedSampleCount, 4)
        XCTAssertEqual(detector.summary.silentSampleCount, 2)
        XCTAssertEqual(detector.summary.silentRatio, 0.5)
    }

    func testNegativeInfinityEntersWhileUnavailableAndNonFiniteDoNotMutate() {
        var detector = SilenceHysteresis()

        XCTAssertTrue(detector.observe(.negativeInfinity))
        XCTAssertTrue(detector.observe(.unavailable))
        XCTAssertTrue(detector.observe(.finite(.nan)))
        XCTAssertTrue(detector.observe(.negativeInfinity))

        XCTAssertEqual(detector.summary.observedSampleCount, 2)
        XCTAssertEqual(detector.summary.silentSampleCount, 2)
        XCTAssertTrue(detector.summary.isEntirelySilent)
    }

    func testSummaryCountsStateAfterEachDeterministicTransition() {
        var detector = SilenceHysteresis()
        let readings: [LoudnessReading] = [
            .finite(-80),
            .finite(-72),
            .finite(-60),
            .finite(-69),
            .finite(-70)
        ]

        readings.forEach { detector.observe($0) }

        XCTAssertEqual(detector.summary.observedSampleCount, 5)
        XCTAssertEqual(detector.summary.silentSampleCount, 3)
        XCTAssertEqual(detector.summary.silentRatio ?? .nan, 0.6, accuracy: 1e-12)
        XCTAssertFalse(detector.summary.isEntirelySilent)
    }

    func testNoObservationsDoNotMasqueradeAsSilence() {
        let summary = SilenceHysteresis().summary

        XCTAssertEqual(summary.observedSampleCount, 0)
        XCTAssertEqual(summary.silentSampleCount, 0)
        XCTAssertNil(summary.silentRatio)
        XCTAssertFalse(summary.isEntirelySilent)
    }

    func testMusicUnderstandingMomentaryTimelineUsesTheSameReducer() {
        let loudness = MusicUnderstandingAnalysis.Loudness(
            integrated: .init(timeSeconds: 0.4, reading: .finite(-40)),
            momentary: [
                .init(timeSeconds: 0.0, reading: .negativeInfinity),
                .init(timeSeconds: 0.1, reading: .finite(-65)),
                .init(timeSeconds: 0.2, reading: .finite(-64)),
                .init(timeSeconds: 0.3, reading: .unavailable)
            ],
            shortTerm: [],
            applePeak: .init(timeSeconds: 0.4, reading: .finite(-1))
        )

        XCTAssertEqual(
            loudness.silenceSummary,
            SilenceHysteresisSummary(observedSampleCount: 3, silentSampleCount: 2)
        )
    }
}
