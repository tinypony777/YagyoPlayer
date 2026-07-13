import AVFoundation
import XCTest

@testable import YagyoPlayer

@MainActor
final class MusicUnderstandingAdapterTests: XCTestCase {
    func testAvailabilityMatchesExecutionEnvironment() {
        #if canImport(MusicUnderstanding)
        if #available(iOS 27.0, *) {
            XCTAssertEqual(MusicUnderstandingAdapter.availability, .available)
        } else {
            XCTAssertEqual(MusicUnderstandingAdapter.availability, .requiresIOS27)
        }
        #else
        XCTAssertEqual(MusicUnderstandingAdapter.availability, .frameworkUnavailable)
        #endif
    }

    func testAppOwnedAnalysisSurvivesJSONRoundTrip() throws {
        let expected = MusicUnderstandingAnalysis(
            analyzedAt: Date(timeIntervalSince1970: 1_725_000_000),
            loudness: .init(
                integrated: .init(timeSeconds: 0, reading: .finite(-18.2)),
                momentary: [
                    .init(timeSeconds: 0.0, reading: .negativeInfinity),
                    .init(timeSeconds: 0.5, reading: .unavailable),
                    .init(timeSeconds: 1.0, reading: .finite(-16.4))
                ],
                shortTerm: [.init(timeSeconds: 3.0, reading: .finite(-17.1))],
                applePeak: .init(timeSeconds: 4.5, reading: .finite(-0.8))
            ),
            rhythm: .init(
                beatSeconds: [0.5, 1.0, 1.5],
                barSeconds: [0.5],
                beatsPerMinute: 120
            ),
            pace: [
                .init(
                    range: .init(startSeconds: 0, durationSeconds: 8),
                    value: 0.62
                )
            ],
            structure: .init(
                sections: [.init(startSeconds: 0, durationSeconds: 8)],
                segments: [.init(startSeconds: 0, durationSeconds: 2)],
                phrases: [.init(startSeconds: 0, durationSeconds: 4)]
            ),
            keys: [
                .init(
                    range: .init(startSeconds: 0, durationSeconds: 8),
                    tonic: "c",
                    mode: "major"
                )
            ],
            instruments: [
                .init(
                    instrument: "drum",
                    activeRanges: [.init(startSeconds: 0, durationSeconds: 8)],
                    activity: [.init(timeSeconds: 1, value: 0.9)]
                )
            ]
        )

        let data = try JSONEncoder().encode(expected)
        let decoded = try JSONDecoder().decode(MusicUnderstandingAnalysis.self, from: data)

        XCTAssertEqual(decoded, expected)
        XCTAssertEqual(decoded.loudness?.maxShortTermLUFS, -17.1)
    }

    func testExecutionErrorsStayAppOwnedAndCancellationWins() {
        let frameworkFailure = MusicUnderstandingAdapter.mappedExecutionError(
            UnexpectedFrameworkError(),
            taskIsCancelled: false
        )
        XCTAssertEqual(frameworkFailure as? MusicUnderstandingAdapterError, .analysisFailed)

        let invalidResult = MusicUnderstandingAdapterError.invalidResult("loudness.peak")
        let preservedFailure = MusicUnderstandingAdapter.mappedExecutionError(
            invalidResult,
            taskIsCancelled: false
        )
        XCTAssertEqual(preservedFailure as? MusicUnderstandingAdapterError, invalidResult)

        let cancelledFailure = MusicUnderstandingAdapter.mappedExecutionError(
            UnexpectedFrameworkError(),
            taskIsCancelled: true
        )
        XCTAssertTrue(cancelledFailure is CancellationError)
    }

    func testScalarNormalizationRejectsNonFiniteAndNegativeTime() throws {
        XCTAssertEqual(
            try MusicUnderstandingAdapter.loudnessReading(-.infinity, field: "loudness"),
            .negativeInfinity
        )
        XCTAssertEqual(
            try MusicUnderstandingAdapter.loudnessReading(-12.5, field: "loudness"),
            .finite(-12.5)
        )

        for value in [Float.nan, .infinity] {
            XCTAssertThrowsError(
                try MusicUnderstandingAdapter.loudnessReading(value, field: "loudness")
            ) { error in
                XCTAssertEqual(
                    error as? MusicUnderstandingAdapterError,
                    .invalidResult("loudness")
                )
            }
        }

        XCTAssertThrowsError(
            try MusicUnderstandingAdapter.seconds(
                CMTime(value: -1, timescale: 1),
                field: "time"
            )
        )
        XCTAssertThrowsError(
            try MusicUnderstandingAdapter.seconds(.invalid, field: "time")
        )
    }

    #if MUSIC_UNDERSTANDING_CAPABILITY_TEST
    /// Phase 0 の明示実行用。通常の unit test では ML 解析時間を持ち込まない。
    /// capability 用 compilation condition と実行環境変数を渡した iOS 27 実行時だけ、
    /// ローカル CAF -> AVAsset -> Apple framework -> app-owned 型を端から端まで通す。
    func testAnalyzesSyntheticLocalAssetWhenCapabilityTestEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_MUSIC_UNDERSTANDING_CAPABILITY_TEST"] == "1" else {
            XCTFail("RUN_MUSIC_UNDERSTANDING_CAPABILITY_TEST=1 is required")
            return
        }
        guard #available(iOS 27.0, *) else {
            XCTFail("Music Understanding capability test requires iOS 27")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("music-understanding-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeRhythmicFixture(to: url)

        let analysis = try await MusicUnderstandingAdapter.analyze(url: url)
        let kitsunebi = try KitsunebiAnalyzer.analyze(url: url)

        XCTAssertEqual(analysis.schemaVersion, MusicUnderstandingAnalysis.currentSchemaVersion)
        XCTAssertEqual(analysis.analyzerIdentifier, MusicUnderstandingAnalysis.analyzerIdentifier)
        let loudness = try XCTUnwrap(analysis.loudness)
        XCTAssertNotNil(loudness.integrated.reading.finiteValue)
        XCTAssertNotNil(loudness.applePeak.reading.finiteValue)
        let rhythm = try XCTUnwrap(analysis.rhythm)
        XCTAssertFalse(rhythm.beatSeconds.isEmpty)
        XCTAssertFalse(rhythm.barSeconds.isEmpty)
        XCTAssertEqual(try XCTUnwrap(rhythm.beatsPerMinute), 120, accuracy: 0.1)
        XCTAssertFalse(analysis.pace.isEmpty)
        let structure = try XCTUnwrap(analysis.structure)
        XCTAssertFalse(structure.sections.isEmpty)
        XCTAssertFalse(structure.segments.isEmpty)
        XCTAssertFalse(structure.phrases.isEmpty)
        XCTAssertFalse(analysis.keys.isEmpty)
        XCTAssertFalse(analysis.instruments.isEmpty)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let evidence = try encoder.encode(
            CapabilityEvidence(analysis: analysis, kitsunebi: kitsunebi)
        )
        let attachment = XCTAttachment(data: evidence, uniformTypeIdentifier: "public.json")
        attachment.name = "music-understanding-kitsunebi-comparison.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCancellationReturnsCancellationError() async throws {
        guard #available(iOS 27.0, *) else {
            XCTFail("Music Understanding capability test requires iOS 27")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("music-understanding-cancel-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeRhythmicFixture(to: url)

        let task = Task {
            try await MusicUnderstandingAdapter.analyze(url: url)
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled analysis unexpectedly succeeded")
        } catch is CancellationError {
            // Expected app-owned cancellation boundary.
        } catch {
            XCTFail("Expected CancellationError, received \(type(of: error))")
        }
    }

    func testInvalidAssetReturnsAppOwnedFailure() async {
        guard #available(iOS 27.0, *) else {
            XCTFail("Music Understanding capability test requires iOS 27")
            return
        }

        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-music-understanding-\(UUID().uuidString).caf")

        do {
            _ = try await MusicUnderstandingAdapter.analyze(url: missingURL)
            XCTFail("Missing asset unexpectedly analyzed")
        } catch let error as MusicUnderstandingAdapterError {
            XCTAssertEqual(error, .analysisFailed)
        } catch {
            XCTFail("Framework error escaped adapter: \(type(of: error))")
        }
    }

    private static func writeRhythmicFixture(to url: URL) throws {
        let sampleRate = 44_100.0
        let channelCount: AVAudioChannelCount = 2
        let durationSeconds = 24.0
        let frameCapacity: AVAudioFrameCount = 4_096
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channelCount
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            XCTFail("Could not create fixture format")
            return
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let totalFrames = Int(sampleRate * durationSeconds)
        var writtenFrames = 0

        // 120 BPM、4/4、C-Am-F-G の決定論的な簡易素材。
        let roots = [261.63, 220.00, 174.61, 196.00]
        while writtenFrames < totalFrames {
            let frameCount = min(Int(frameCapacity), totalFrames - writtenFrames)
            buffer.frameLength = AVAudioFrameCount(frameCount)
            guard let channels = buffer.floatChannelData else {
                XCTFail("Could not access fixture channel data")
                return
            }

            for localFrame in 0..<frameCount {
                let absoluteFrame = writtenFrames + localFrame
                let time = Double(absoluteFrame) / sampleRate
                let barIndex = Int(time / 2.0)
                let root = roots[barIndex % roots.count]
                let chord = 0.055 * sin(2 * .pi * root * time)
                    + 0.040 * sin(2 * .pi * root * 1.25 * time)
                    + 0.035 * sin(2 * .pi * root * 1.5 * time)

                let beatPhase = time.truncatingRemainder(dividingBy: 0.5)
                let beatEnvelope = beatPhase < 0.09 ? exp(-beatPhase * 38) : 0
                let beat = 0.22 * beatEnvelope * sin(2 * .pi * 72 * time)
                let sample = Float(chord + beat)
                channels[0][localFrame] = sample
                channels[1][localFrame] = sample * 0.96
            }

            try file.write(from: buffer)
            writtenFrames += frameCount
        }
    }

    private struct CapabilityEvidence: Encodable {
        var musicUnderstanding: MusicUnderstandingAnalysis
        var kitsunebiIntegratedLUFS: Double?
        var kitsunebiMaxShortTermLUFS: Double?
        var kitsunebiSamplePeakDBFS: Double?
        var kitsunebiTruePeakDBTP: Double?
        var integratedDeltaLU: Double?
        var maxShortTermDeltaLU: Double?

        init(analysis: MusicUnderstandingAnalysis, kitsunebi: TobariMeasurement) {
            musicUnderstanding = analysis
            kitsunebiIntegratedLUFS = kitsunebi.integratedLUFS
            kitsunebiMaxShortTermLUFS = kitsunebi.maxShortTermLUFS
            kitsunebiSamplePeakDBFS = kitsunebi.samplePeakDBFS
            kitsunebiTruePeakDBTP = kitsunebi.truePeakDBTP
            integratedDeltaLU = Self.delta(
                analysis.loudness?.integrated.reading.finiteValue,
                kitsunebi.integratedLUFS
            )
            maxShortTermDeltaLU = Self.delta(
                analysis.loudness?.maxShortTermLUFS,
                kitsunebi.maxShortTermLUFS
            )
        }

        private static func delta(_ lhs: Double?, _ rhs: Double?) -> Double? {
            guard let lhs, let rhs else { return nil }
            return lhs - rhs
        }
    }
    #endif

    private struct UnexpectedFrameworkError: Error {}
}
