import XCTest

@testable import YagyoPlayer

@MainActor
final class FeatureAnalysisSessionTests: XCTestCase {
    private let fingerprint = String(repeating: "a", count: 64)
    private let audioURL = URL(fileURLWithPath: "/tmp/session-test.caf")

    func testAnalyzePublishesReadySnapshot() async {
        let expected = makeSnapshot()
        let session = FeatureAnalysisSession { url, sourceFingerprint in
            XCTAssertEqual(url, self.audioURL)
            XCTAssertEqual(sourceFingerprint, self.fingerprint)
            return expected
        }

        await session.analyze(
            url: audioURL,
            sourceFingerprint: fingerprint
        )

        XCTAssertEqual(session.state, .ready(expected))
    }

    func testAnalyzePublishesLocalizedFailureWithoutLeakingPartialSnapshot() async {
        let session = FeatureAnalysisSession { _, _ in
            throw FeatureSnapshotValidationError.invalidSourceFingerprint
        }

        await session.analyze(
            url: audioURL,
            sourceFingerprint: fingerprint
        )

        XCTAssertEqual(
            session.state,
            .unavailable("音源フィンガープリントが有効なSHA-256ではありません。")
        )
    }

    func testCancelledAnalysisReturnsToIdleWithoutPublishingFailure() async {
        let didStart = expectation(description: "analysis started")
        let session = FeatureAnalysisSession { _, _ in
            didStart.fulfill()
            try await Task.sleep(for: .seconds(30))
            return self.makeSnapshot()
        }
        let task = Task {
            await session.analyze(
                url: audioURL,
                sourceFingerprint: fingerprint
            )
        }

        await fulfillment(of: [didStart], timeout: 1)
        task.cancel()
        await task.value

        XCTAssertEqual(session.state, .idle)
    }

    func testUnavailableReasonCanBePublishedWithoutStartingAnalysis() {
        let session = FeatureAnalysisSession { _, _ in
            XCTFail("Analysis must not start without a valid track request")
            return self.makeSnapshot()
        }

        session.markUnavailable("曲を読み込むと解析できます。")

        XCTAssertEqual(session.state, .unavailable("曲を読み込むと解析できます。"))
    }

    private func makeSnapshot() -> FeatureSnapshot {
        let createdAt = Date(timeIntervalSince1970: 1_784_000_000)
        return FeatureSnapshot(
            schemaVersion: FeatureSnapshot.currentSchemaVersion,
            sourceFingerprint: fingerprint,
            analyzerVersion: FeatureSnapshot.currentAnalyzerVersion,
            compatibilityKey: FeatureSnapshot.currentCompatibilityKey,
            availability: .complete,
            boundedFiniteFeatures: .init(
                musicUnderstanding: .init(
                    beatsPerMinute: 120,
                    beatCount: 48,
                    barCount: 12,
                    meanPace: 0.5,
                    sectionCount: 3,
                    segmentCount: 6,
                    phraseCount: 8,
                    silenceSummary: .init(
                        observedSampleCount: 10,
                        silentSampleCount: 2
                    ),
                    dominantKey: .init(
                        tonic: "c",
                        mode: "major",
                        observedDurationSeconds: 12
                    ),
                    instruments: []
                ),
                kitsunebi: TobariMetrics(
                    analyzerVersion: TobariMetrics.currentAnalyzerVersion,
                    contentHash: fingerprint,
                    analyzedAt: createdAt,
                    sampleRate: 48_000,
                    durationSeconds: 12,
                    channelCount: 2,
                    integratedLUFS: -18,
                    maxShortTermLUFS: -16,
                    samplePeakDBFS: -1,
                    truePeakDBTP: -0.8,
                    clipRunCount: 0,
                    clipRunSeconds: [],
                    stereoCorrelation: 0.9
                )
            ),
            createdAt: createdAt
        )
    }
}
