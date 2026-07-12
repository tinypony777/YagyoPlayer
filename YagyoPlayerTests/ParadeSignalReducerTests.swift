import XCTest
@testable import YagyoPlayer

final class ParadeSignalReducerTests: XCTestCase {
    private let configuration = ParadeSignalConfiguration.production

    private func input(_ time: TimeInterval, _ level: Double?, playing: Bool = true) -> ParadeSignalInput {
        ParadeSignalInput(isPlaying: playing, level: level, sampledAt: time)
    }

    func testStoppedUnavailableAndFiniteClampingAreDistinct() {
        var reducer = ParadeSignalReducer(configuration: configuration)
        XCTAssertEqual(reducer.ingest(input(0, 0.5, playing: false)).activity, .stopped)
        XCTAssertEqual(reducer.ingest(input(1, nil)).activity, .unavailable)
        XCTAssertEqual(reducer.ingest(input(2, .nan)).activity, .unavailable)
        XCTAssertEqual(reducer.ingest(input(3, 2)).level, 1)
        XCTAssertEqual(reducer.ingest(input(4, -1)).level, 0)
    }

    func testQuietRequiresDwellAndExitsWithHysteresis() {
        var reducer = ParadeSignalReducer(configuration: configuration)
        _ = reducer.ingest(input(0, 0.05))
        _ = reducer.ingest(input(0.35, 0.05))
        XCTAssertEqual(reducer.ingest(input(0.69, 0.05)).activity, .normal)
        XCTAssertEqual(reducer.ingest(input(0.70, 0.05)).activity, .quietProxy)
        XCTAssertEqual(reducer.ingest(input(0.80, 0.10)).activity, .quietProxy)
        XCTAssertEqual(reducer.ingest(input(0.90, 0.14)).activity, .normal)
    }

    func testLoudStartSeedsBaselineWithoutStrongRise() {
        var reducer = ParadeSignalReducer(configuration: configuration)
        XCTAssertEqual(reducer.ingest(input(0, 0.90)).strongPhase, .inactive)
        XCTAssertEqual(reducer.ingest(input(0.31, 0.90)).strongPhase, .inactive)
        XCTAssertEqual(reducer.snapshot.strongSequence, 0)
    }

    func testStrongRiseFiresOnceMovesThroughPhasesAndRequiresRearm() {
        var reducer = ParadeSignalReducer(configuration: configuration)
        _ = reducer.ingest(input(0, 0.20))
        _ = reducer.ingest(input(0.31, 0.20))
        XCTAssertEqual(reducer.ingest(input(0.40, 0.80)).strongPhase, .anticipate)
        XCTAssertEqual(reducer.ingest(input(0.48, 0.80)).strongPhase, .open)
        XCTAssertEqual(reducer.ingest(input(0.75, 0.80)).strongPhase, .recover)
        XCTAssertEqual(reducer.ingest(input(1.00, 0.80)).strongPhase, .inactive)
        XCTAssertEqual(reducer.snapshot.strongSequence, 1)
        _ = reducer.ingest(input(1.10, 0.20))
        XCTAssertEqual(reducer.ingest(input(1.20, 0.80)).strongSequence, 2)
    }

    func testLargeOrBackwardSampleGapReseedsWithoutStrongRise() {
        var reducer = ParadeSignalReducer(configuration: configuration)
        _ = reducer.ingest(input(1.0, 0.10))
        XCTAssertEqual(reducer.ingest(input(2.0, 0.90)).strongSequence, 0)
        XCTAssertEqual(reducer.ingest(input(1.5, 0.90)).strongSequence, 0)
    }

    func testPreviewFactoryUsesPresentationDefaultsAndLevelBands() {
        XCTAssertEqual(ParadeSignalSnapshot.preview(activity: .stopped).level, 0)
        XCTAssertEqual(ParadeSignalSnapshot.preview(activity: .unavailable).levelBand, .unavailable)
        XCTAssertEqual(ParadeSignalSnapshot.preview(activity: .quietProxy).level, 0.05)
        XCTAssertEqual(ParadeSignalSnapshot.preview(activity: .quietProxy).levelBand, .low)
        XCTAssertEqual(ParadeSignalSnapshot.preview(activity: .normal).level, 0.5)
        XCTAssertEqual(ParadeSignalSnapshot.preview(activity: .normal, level: 0.199).levelBand, .low)
        XCTAssertEqual(ParadeSignalSnapshot.preview(activity: .normal, level: 0.20).levelBand, .medium)
        XCTAssertEqual(ParadeSignalSnapshot.preview(activity: .normal, level: 0.649).levelBand, .medium)
        XCTAssertEqual(ParadeSignalSnapshot.preview(activity: .normal, level: 0.65).levelBand, .high)
    }

    func testParadeMotionPreferenceUsesSystemSettingUnlessPreviewOverrideIsExplicit() {
        XCTAssertFalse(
            ParadeMotionPreference.resolve(
                systemReduceMotion: false,
                previewOverride: nil
            )
        )
        XCTAssertTrue(
            ParadeMotionPreference.resolve(
                systemReduceMotion: true,
                previewOverride: nil
            )
        )
        XCTAssertTrue(
            ParadeMotionPreference.resolve(
                systemReduceMotion: false,
                previewOverride: true
            )
        )
        XCTAssertFalse(
            ParadeMotionPreference.resolve(
                systemReduceMotion: true,
                previewOverride: false
            )
        )
    }

    func testAccessibilityValueDescribesQuietUnavailableAndStrongStatesExactly() {
        XCTAssertEqual(
            ParadeSignalSnapshot.preview(activity: .quietProxy)
                .accessibilityValue(residentName: "唐傘", isUshimitsu: false),
            "再生中、音量は低め、先導は唐傘"
        )
        XCTAssertEqual(
            ParadeSignalSnapshot.preview(activity: .unavailable)
                .accessibilityValue(residentName: "河童", isUshimitsu: true),
            "再生中、音量表示を利用できません、先導は河童、丑三つ時"
        )
        XCTAssertEqual(
            ParadeSignalSnapshot.preview(activity: .normal, strongPhase: .open)
                .accessibilityValue(residentName: "天狗", isUshimitsu: false),
            "再生中、音量が強く上昇、先導は天狗"
        )
    }

    func testStaticProcessionKeepsLeadingKarakasaAndMarkerInsideCanvas() {
        let x = ParadeProcessionLayout.xPosition(
            index: 0,
            walkerCount: 8,
            gap: 86,
            speed: 0,
            time: 1_000
        )

        XCTAssertEqual(x, 12, accuracy: 0.000_1)
        XCTAssertGreaterThanOrEqual(x, 0)
        XCTAssertLessThanOrEqual(x + 80, 390)
        XCTAssertGreaterThan(x + 40, 0)
        XCTAssertLessThan(x + 40, 390)
    }

    func testAnimatedProcessionWrapsOnlyAfterCrossingOffscreenBoundary() {
        let gap = 86.0
        let speed = 46.0
        let cycle = gap * 8
        let cycleTime = cycle / speed

        XCTAssertEqual(
            ParadeProcessionLayout.xPosition(
                index: 0, walkerCount: 8, gap: gap, speed: speed, time: 0
            ),
            -70,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ParadeProcessionLayout.xPosition(
                index: 0, walkerCount: 8, gap: gap, speed: speed, time: cycleTime
            ),
            -70,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ParadeProcessionLayout.xPosition(
                index: 1, walkerCount: 8, gap: gap, speed: speed, time: 85 / speed
            ),
            -69,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ParadeProcessionLayout.xPosition(
                index: 1, walkerCount: 8, gap: gap, speed: speed, time: 86 / speed
            ),
            -70,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ParadeProcessionLayout.xPosition(
                index: 1, walkerCount: 8, gap: gap, speed: speed, time: 87 / speed
            ),
            617,
            accuracy: 0.000_1
        )
    }

    func testCircularWaveformPresentationKeepsStoppedLowAndUnavailableDistinct() {
        let stopped = CircularWaveformPresentation(activity: .stopped, levelBand: .high)
        let low = CircularWaveformPresentation(activity: .quietProxy, levelBand: .low)
        let unavailable = CircularWaveformPresentation(activity: .unavailable, levelBand: .low)

        XCTAssertEqual(stopped, .stopped)
        XCTAssertEqual(low, .low)
        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertFalse(stopped.usesProgressPhase)
        XCTAssertTrue(low.usesProgressPhase)
        XCTAssertFalse(unavailable.usesProgressPhase)
        XCTAssertEqual(stopped.staticLength, 12)
        XCTAssertEqual(low.staticLength, 14)
        XCTAssertEqual(unavailable.staticLength, 20)
        XCTAssertTrue(low.usesAccentColor)
        XCTAssertFalse(unavailable.usesAccentColor)
    }
}
