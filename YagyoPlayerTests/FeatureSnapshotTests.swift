import Foundation
import XCTest

@testable import YagyoPlayer

@MainActor
final class FeatureSnapshotTests: XCTestCase {
    private let fingerprint = String(repeating: "a", count: 64)
    private let createdAt = Date(timeIntervalSince1970: 1_784_000_000)

    func testExtractorBuildsFixedSizeSnapshotFromMusicUnderstandingAndKitsunebi() throws {
        let snapshot = try BoundedDSPFeatureExtractor.makeSnapshot(
            sourceFingerprint: fingerprint,
            musicUnderstanding: makeMusicAnalysis(instrumentCount: 20),
            kitsunebi: makeMeasurement(),
            createdAt: createdAt
        )

        XCTAssertEqual(snapshot.schemaVersion, FeatureSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.analyzerVersion, FeatureSnapshot.currentAnalyzerVersion)
        XCTAssertEqual(snapshot.compatibilityKey, FeatureSnapshot.currentCompatibilityKey)
        XCTAssertEqual(snapshot.availability, .complete)
        XCTAssertEqual(snapshot.sourceFingerprint, fingerprint)
        XCTAssertEqual(snapshot.createdAt, createdAt)

        let music = snapshot.boundedFiniteFeatures.musicUnderstanding
        XCTAssertEqual(music.beatsPerMinute, 120)
        XCTAssertEqual(music.beatCount, 4)
        XCTAssertEqual(music.barCount, 1)
        XCTAssertEqual(music.meanPace ?? .nan, 0.5, accuracy: 1e-12)
        XCTAssertEqual(music.sectionCount, 1)
        XCTAssertEqual(music.segmentCount, 2)
        XCTAssertEqual(music.phraseCount, 2)
        XCTAssertEqual(music.silenceSummary.observedSampleCount, 3)
        XCTAssertEqual(music.silenceSummary.silentSampleCount, 2)
        XCTAssertEqual(music.dominantKey?.tonic, "a")
        XCTAssertEqual(music.dominantKey?.mode, "minor")
        XCTAssertEqual(music.instruments.count, BoundedDSPFeatureExtractor.maximumInstrumentCount)
        XCTAssertEqual(music.instruments.first?.identifier, "instrument-19")
        XCTAssertEqual(music.instruments.last?.identifier, "instrument-04")

        let safety = snapshot.boundedFiniteFeatures.kitsunebi
        XCTAssertEqual(safety.analyzerVersion, TobariMetrics.currentAnalyzerVersion)
        XCTAssertEqual(safety.contentHash, fingerprint)
        XCTAssertEqual(safety.analyzedAt, createdAt)
        XCTAssertEqual(safety.integratedLUFS, -18.2)
        XCTAssertEqual(safety.truePeakDBTP, -0.4)
        XCTAssertEqual(safety.clipRunCount, 1)
        XCTAssertNoThrow(try snapshot.validateForCaching())
    }

    func testExtractorRejectsInvalidFingerprintAndNonFiniteValues() {
        XCTAssertThrowsError(
            try BoundedDSPFeatureExtractor.makeSnapshot(
                sourceFingerprint: "not-a-sha256",
                musicUnderstanding: makeMusicAnalysis(),
                kitsunebi: makeMeasurement(),
                createdAt: createdAt
            )
        ) { error in
            XCTAssertEqual(
                error as? FeatureSnapshotValidationError,
                .invalidSourceFingerprint
            )
        }

        var invalidMeasurement = makeMeasurement()
        invalidMeasurement.samplePeakDBFS = .nan
        XCTAssertThrowsError(
            try BoundedDSPFeatureExtractor.makeSnapshot(
                sourceFingerprint: fingerprint,
                musicUnderstanding: makeMusicAnalysis(),
                kitsunebi: invalidMeasurement,
                createdAt: createdAt
            )
        ) { error in
            XCTAssertEqual(
                error as? FeatureSnapshotValidationError,
                .nonFinite("boundedFiniteFeatures.kitsunebi.samplePeakDBFS")
            )
        }

        var invalidMusicUnderstanding = makeMusicAnalysis()
        invalidMusicUnderstanding.pace[0].value = .infinity
        XCTAssertThrowsError(
            try BoundedDSPFeatureExtractor.makeSnapshot(
                sourceFingerprint: fingerprint,
                musicUnderstanding: invalidMusicUnderstanding,
                kitsunebi: makeMeasurement(),
                createdAt: createdAt
            )
        ) { error in
            XCTAssertEqual(
                error as? FeatureSnapshotValidationError,
                .nonFinite("musicUnderstanding.pace[0].value")
            )
        }
    }

    func testSnapshotJSONRoundTripNeverPersistsNonFiniteLoudness() throws {
        let snapshot = try BoundedDSPFeatureExtractor.makeSnapshot(
            sourceFingerprint: fingerprint,
            musicUnderstanding: makeMusicAnalysis(),
            kitsunebi: makeMeasurement(),
            createdAt: createdAt
        )

        let data = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("NaN"))
        XCTAssertFalse(json.contains("Infinity"))
        XCTAssertEqual(try JSONDecoder().decode(FeatureSnapshot.self, from: data), snapshot)
    }

    func testCacheLoadsCurrentSnapshotAndPurgesStaleOrCorruptEntries() async throws {
        let directory = temporaryDirectory(name: "feature-cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FeatureSnapshotCache(directoryURL: directory)
        let snapshot = try makeSnapshot()

        try await cache.store(snapshot)
        let restored = try await cache.load(sourceFingerprint: fingerprint)
        XCTAssertEqual(restored, snapshot)

        var stale = snapshot
        stale.schemaVersion -= 1
        try JSONEncoder().encode(stale).write(
            to: directory.appendingPathComponent("\(fingerprint).json"),
            options: .atomic
        )
        let staleResult = try await cache.load(sourceFingerprint: fingerprint)
        XCTAssertNil(staleResult)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("\(fingerprint).json").path
            )
        )

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{broken".utf8).write(
            to: directory.appendingPathComponent("\(fingerprint).json"),
            options: .atomic
        )
        let corruptResult = try await cache.load(sourceFingerprint: fingerprint)
        XCTAssertNil(corruptResult)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("\(fingerprint).json").path
            )
        )
    }

    func testCacheRejectsInvalidSnapshotWithoutWriting() async throws {
        let directory = temporaryDirectory(name: "feature-invalid-cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FeatureSnapshotCache(directoryURL: directory)
        var snapshot = try makeSnapshot()
        snapshot.compatibilityKey = "old-runtime"

        do {
            try await cache.store(snapshot)
            XCTFail("Invalid snapshot unexpectedly reached disk")
        } catch let error as FeatureSnapshotValidationError {
            XCTAssertEqual(error, .versionMismatch("compatibilityKey"))
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("\(fingerprint).json").path
            )
        )
    }

    func testOfflineServiceUsesCacheAndDoesNotRepeatAnalysis() async throws {
        let directory = temporaryDirectory(name: "feature-service-cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FeatureSnapshotCache(directoryURL: directory)
        let recorder = AnalysisInvocationRecorder()
        let analysis = makeMusicAnalysis()
        let measurement = makeMeasurement()
        let createdAt = self.createdAt
        let service = OfflineFeatureAnalysisService(
            cache: cache,
            musicAnalyzer: { _ in
                await recorder.recordMusicUnderstanding()
                return analysis
            },
            kitsunebiAnalyzer: { _ in
                await recorder.recordKitsunebi()
                return measurement
            },
            clock: { createdAt }
        )
        let url = URL(fileURLWithPath: "/tmp/local-audio.caf")

        let first = try await service.snapshot(for: url, sourceFingerprint: fingerprint)
        let second = try await service.snapshot(for: url, sourceFingerprint: fingerprint)
        let counts = await recorder.counts

        XCTAssertEqual(first, second)
        XCTAssertEqual(counts.musicUnderstanding, 1)
        XCTAssertEqual(counts.kitsunebi, 1)
    }

    func testOfflineServiceCancellationDoesNotPublishCacheEntry() async throws {
        let directory = temporaryDirectory(name: "feature-cancel-cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FeatureSnapshotCache(directoryURL: directory)
        let analysis = makeMusicAnalysis()
        let measurement = makeMeasurement()
        let createdAt = self.createdAt
        let service = OfflineFeatureAnalysisService(
            cache: cache,
            musicAnalyzer: { _ in
                try await Task.sleep(for: .seconds(30))
                return analysis
            },
            kitsunebiAnalyzer: { _ in measurement },
            clock: { createdAt }
        )
        let task = Task {
            try await service.snapshot(
                for: URL(fileURLWithPath: "/tmp/local-audio.caf"),
                sourceFingerprint: fingerprint
            )
        }

        await Task.yield()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled analysis unexpectedly succeeded")
        } catch is CancellationError {
            // Expected.
        }

        let cachedAfterCancellation = try await cache.load(sourceFingerprint: fingerprint)
        XCTAssertNil(cachedAfterCancellation)
    }

    private func makeSnapshot() throws -> FeatureSnapshot {
        try BoundedDSPFeatureExtractor.makeSnapshot(
            sourceFingerprint: fingerprint,
            musicUnderstanding: makeMusicAnalysis(),
            kitsunebi: makeMeasurement(),
            createdAt: createdAt
        )
    }

    private func makeMusicAnalysis(instrumentCount: Int = 2) -> MusicUnderstandingAnalysis {
        MusicUnderstandingAnalysis(
            analyzedAt: createdAt,
            loudness: .init(
                integrated: .init(timeSeconds: 0, reading: .finite(-18.2)),
                momentary: [
                    .init(timeSeconds: 0, reading: .negativeInfinity),
                    .init(timeSeconds: 0.1, reading: .finite(-66)),
                    .init(timeSeconds: 0.2, reading: .finite(-64))
                ],
                shortTerm: [.init(timeSeconds: 3, reading: .finite(-17.4))],
                applePeak: .init(timeSeconds: 4, reading: .finite(-0.8))
            ),
            rhythm: .init(
                beatSeconds: [0.5, 1, 1.5, 2],
                barSeconds: [0.5],
                beatsPerMinute: 120
            ),
            pace: [
                .init(range: .init(startSeconds: 0, durationSeconds: 4), value: 0.2),
                .init(range: .init(startSeconds: 4, durationSeconds: 4), value: 0.8)
            ],
            structure: .init(
                sections: [.init(startSeconds: 0, durationSeconds: 8)],
                segments: [
                    .init(startSeconds: 0, durationSeconds: 4),
                    .init(startSeconds: 4, durationSeconds: 4)
                ],
                phrases: [
                    .init(startSeconds: 0, durationSeconds: 4),
                    .init(startSeconds: 4, durationSeconds: 4)
                ]
            ),
            keys: [
                .init(
                    range: .init(startSeconds: 0, durationSeconds: 2),
                    tonic: "c",
                    mode: "major"
                ),
                .init(
                    range: .init(startSeconds: 2, durationSeconds: 6),
                    tonic: "a",
                    mode: "minor"
                )
            ],
            instruments: (0..<instrumentCount).map { index in
                .init(
                    instrument: String(format: "instrument-%02d", index),
                    activeRanges: [.init(startSeconds: 0, durationSeconds: 8)],
                    activity: [.init(timeSeconds: 1, value: Double(index))]
                )
            }
        )
    }

    private func makeMeasurement() -> TobariMeasurement {
        TobariMeasurement(
            sampleRate: 48_000,
            channelCount: 2,
            frameCount: 384_000,
            integratedLUFS: -18.2,
            maxShortTermLUFS: -17.4,
            samplePeakDBFS: -0.8,
            truePeakDBTP: -0.4,
            clipRunCount: 1,
            clipRunSeconds: [3.2],
            stereoCorrelation: 0.92
        )
    }

    private func temporaryDirectory(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor AnalysisInvocationRecorder {
    private var musicUnderstandingCount = 0
    private var kitsunebiCount = 0

    var counts: (musicUnderstanding: Int, kitsunebi: Int) {
        (musicUnderstandingCount, kitsunebiCount)
    }

    func recordMusicUnderstanding() {
        musicUnderstandingCount += 1
    }

    func recordKitsunebi() {
        kitsunebiCount += 1
    }
}
