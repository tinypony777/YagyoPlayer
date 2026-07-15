import SwiftUI
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

    func testWoodblockPoseDerivesQuietStrongAndReducedMotionFromOneBaseArt() {
        XCTAssertEqual(
            WoodblockYokaiPose.resolve(
                activity: .quietProxy,
                strongPhase: .inactive,
                reduceMotion: false
            ),
            WoodblockYokaiPose(scale: 0.95, verticalOffset: 2, opacity: 0.78)
        )
        XCTAssertEqual(
            WoodblockYokaiPose.resolve(
                activity: .normal,
                strongPhase: .open,
                reduceMotion: false
            ),
            WoodblockYokaiPose(scale: 1.07, verticalOffset: -2, opacity: 1)
        )
        XCTAssertEqual(
            WoodblockYokaiPose.resolve(
                activity: .normal,
                strongPhase: .open,
                reduceMotion: true
            ),
            WoodblockYokaiPose(scale: 1, verticalOffset: 0, opacity: 1)
        )
    }

    func testWaveformBandCentersAConsistentlyLoudCompressedTrack() {
        var reducer = ParadeSignalReducer(configuration: configuration)

        var snapshot = reducer.ingest(input(0, 0.82))
        XCTAssertEqual(snapshot.levelBand, .high)
        XCTAssertEqual(snapshot.waveformLevelBand, .medium)
        XCTAssertEqual(snapshot.waveformLevel, 0.5, accuracy: 0.000_1)

        for sample in 1...20 {
            snapshot = reducer.ingest(input(Double(sample) * 0.10, 0.82))
        }

        XCTAssertEqual(snapshot.levelBand, .high)
        XCTAssertEqual(snapshot.waveformLevelBand, .medium)
        XCTAssertEqual(snapshot.waveformLevel, 0.5, accuracy: 0.000_1)
    }

    func testWaveformBandRevealsSmallRelativeSectionChanges() {
        var reducer = ParadeSignalReducer(configuration: configuration)

        _ = reducer.ingest(input(0, 0.78))
        for sample in 1...10 {
            _ = reducer.ingest(input(Double(sample) * 0.10, 0.78))
        }

        var snapshot = reducer.ingest(input(1.10, 0.82))
        XCTAssertEqual(snapshot.levelBand, .high)
        XCTAssertEqual(snapshot.waveformLevelBand, .high)
        XCTAssertGreaterThanOrEqual(snapshot.waveformLevel, 0.70)

        for sample in 12...16 {
            snapshot = reducer.ingest(input(Double(sample) * 0.10, 0.78))
            XCTAssertEqual(snapshot.waveformLevelBand, .high, "high state should not flicker during hold")
        }

        snapshot = reducer.ingest(input(1.70, 0.78))
        XCTAssertEqual(snapshot.levelBand, .high)
        XCTAssertEqual(snapshot.waveformLevelBand, .low)
        XCTAssertLessThanOrEqual(snapshot.waveformLevel, 0.30)
    }

    func testWaveformDynamicsResetBeforeTheNextTrack() {
        var reducer = ParadeSignalReducer(configuration: configuration)

        _ = reducer.ingest(input(0, 0.50))
        for sample in 1...5 {
            _ = reducer.ingest(input(Double(sample) * 0.10, 0.50))
        }
        _ = reducer.ingest(input(0.60, 0.55))
        XCTAssertEqual(reducer.snapshot.waveformLevelBand, .high)

        var snapshot = reducer.reset(isPlaying: false)
        XCTAssertEqual(snapshot.waveformLevel, 0)
        XCTAssertEqual(snapshot.waveformLevelBand, .low)

        snapshot = reducer.ingest(input(1.0, 0.90))
        XCTAssertEqual(snapshot.levelBand, .high)
        XCTAssertEqual(snapshot.waveformLevel, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(snapshot.waveformLevelBand, .medium)

        snapshot = reducer.ingest(input(1.1, nil))
        XCTAssertEqual(snapshot.waveformLevel, 0)
        XCTAssertEqual(snapshot.waveformLevelBand, .unavailable)
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

    func testWoodblockWaveformPresentationKeepsStoppedLowAndUnavailableDistinct() {
        let stopped = WoodblockWaveformPresentation(activity: .stopped, levelBand: .high)
        let low = WoodblockWaveformPresentation(activity: .quietProxy, levelBand: .low)
        let unavailable = WoodblockWaveformPresentation(activity: .unavailable, levelBand: .low)

        XCTAssertEqual(stopped, .stopped)
        XCTAssertEqual(low, .low)
        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertTrue(low.usesAccentColor)
        XCTAssertFalse(unavailable.usesAccentColor)
        XCTAssertEqual(stopped.centerMark, "止")
        XCTAssertEqual(unavailable.centerMark, "—")
        XCTAssertEqual(low.centerMark, "静")
        XCTAssertEqual(
            WoodblockWaveformPresentation(activity: .normal, levelBand: .medium).centerMark,
            "響"
        )
        XCTAssertEqual(
            WoodblockWaveformPresentation(activity: .normal, levelBand: .high).centerMark,
            "烈"
        )
        XCTAssertEqual(stopped.accessibilityState, "停止")
        XCTAssertEqual(unavailable.accessibilityState, "利用不可")
        XCTAssertEqual(low.accessibilityState, "静か")
    }

    func testWaveformHistoryKeepsEqualSamplesAndEvictsOldestAtLimit() {
        var history = WaveformHistoryBuffer(limit: 3)

        history.append(0.4)
        history.append(0.4)
        history.append(0.8)
        history.append(0.2)

        XCTAssertEqual(history.levels, [0.4, 0.8, 0.2])
    }

    func testWaveformHistoryResetClearClampAndSamplingAreDeterministic() {
        var history = WaveformHistoryBuffer(limit: 4)

        history.reset(to: 2, count: 8)
        XCTAssertEqual(history.levels, [1, 1, 1, 1])
        XCTAssertEqual(history.sampled(count: 2, fallback: 0), [1, 1])

        history.clear()
        XCTAssertEqual(history.sampled(count: 3, fallback: -1), [0, 0, 0])
    }

    func testReducerHistoryTracksTimeSamplesAndClearsForUnavailableOrStopped() {
        var reducer = ParadeSignalReducer(configuration: configuration)

        var snapshot = reducer.ingest(input(0, 0.5))
        XCTAssertEqual(snapshot.waveformHistory.levels.count, 1)

        snapshot = reducer.ingest(input(0.1, 0.5))
        XCTAssertEqual(snapshot.waveformHistory.levels.count, 2)

        snapshot = reducer.ingest(input(0.2, nil))
        XCTAssertTrue(snapshot.waveformHistory.levels.isEmpty)

        snapshot = reducer.reset(isPlaying: false)
        XCTAssertTrue(snapshot.waveformHistory.levels.isEmpty)
    }

    @MainActor
    func testExportsWoodblockWaveformStateBoard() throws {
        try exportWindowArtifact(
            rootView: WoodblockWaveformArtifactBoard(),
            windowWidth: 402,
            windowHeight: 874,
            interfaceStyle: .light,
            attachmentName: "woodblock-waveform-state-board.png"
        )
    }
}

private struct WoodblockWaveformArtifactState: Identifiable {
    let id: String
    let activity: ParadeSignalSnapshot.Activity
    let levelBand: ParadeSignalSnapshot.LevelBand
    let level: Double
    let reduceMotion: Bool
}

private struct WoodblockWaveformArtifactBoard: View {
    private let states = [
        WoodblockWaveformArtifactState(
            id: "stopped", activity: .stopped, levelBand: .high, level: 0, reduceMotion: false
        ),
        WoodblockWaveformArtifactState(
            id: "unavailable", activity: .unavailable, levelBand: .unavailable, level: 0, reduceMotion: false
        ),
        WoodblockWaveformArtifactState(
            id: "low", activity: .quietProxy, levelBand: .low, level: 0.08, reduceMotion: false
        ),
        WoodblockWaveformArtifactState(
            id: "medium", activity: .normal, levelBand: .medium, level: 0.42, reduceMotion: false
        ),
        WoodblockWaveformArtifactState(
            id: "high", activity: .normal, levelBand: .high, level: 0.88, reduceMotion: false
        ),
        WoodblockWaveformArtifactState(
            id: "high · Reduce Motion", activity: .normal, levelBand: .high, level: 0.88, reduceMotion: true
        )
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("版木枠の音の足跡 · 状態見本")
                    .font(.system(.headline, design: .serif))
                    .tracking(2)
                    .foregroundStyle(YagyoPrintColor.ink)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(states) { state in
                        VStack(spacing: 6) {
                            WoodblockWaveform(
                                level: state.level,
                                activity: state.activity,
                                levelBand: state.levelBand,
                                reduceMotionOverride: state.reduceMotion
                            )
                            .frame(height: 112)

                            Text(state.id)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(YagyoPrintColor.inkMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .modernRetroPanel(tone: .paper, radius: 8, padding: 8)
                    }
                }
            }
            .padding(16)
        }
        .background(YagyoPrintColor.canvas.ignoresSafeArea())
    }
}
