import XCTest
@testable import YagyoPlayer

/// 狐火の帳(Step 5 Phase A)の既知信号テスト。
/// 期待値は同一アルゴリズムのPython参照実装(ミラー)から導出した
/// (K-weighting係数・ゲーティング・FIR設計まで1:1で写像して算出)。
/// 997 Hz正弦波の系はEBU Tech 3341の基準系(-20 dBFSステレオ → -20.0 LUFS)と一致する。
final class KitsunebiAnalyzerTests: XCTestCase {
    private let sampleRate = 48000.0

    private func sine(
        frequency: Double,
        amplitude: Double,
        seconds: Double,
        phase: Double = 0
    ) -> [Float] {
        let count = Int(sampleRate * seconds)
        return (0..<count).map { index in
            Float(amplitude * sin(2.0 * .pi * frequency * Double(index) / sampleRate + phase))
        }
    }

    private func analyze(channels: [[Float]], maximumChunkFrames: Int = 65536) -> TobariMeasurement {
        let engine = KitsunebiAnalyzerEngine(
            sampleRate: sampleRate,
            channelCount: channels.count,
            maximumChunkFrames: maximumChunkFrames
        )
        engine.process(channels: channels)
        return engine.finalize()
    }

    // MARK: - T1: EBU基準系

    func testStereoReferenceSineMeasuresMinusTwentyLUFS() {
        let signal = sine(frequency: 997, amplitude: 0.1, seconds: 10)
        let result = analyze(channels: [signal, signal])

        XCTAssertEqual(result.frameCount, 480_000)
        XCTAssertEqual(result.integratedLUFS ?? .nan, -20.0, accuracy: 0.05)
        XCTAssertEqual(result.maxShortTermLUFS ?? .nan, -20.0, accuracy: 0.05)
        XCTAssertEqual(result.samplePeakDBFS ?? .nan, -20.0, accuracy: 0.01)
        XCTAssertEqual(result.truePeakDBTP ?? .nan, -20.0, accuracy: 0.05)
        XCTAssertEqual(result.stereoCorrelation ?? .nan, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result.clipRunCount, 0)
        XCTAssertTrue(result.clipRunSeconds.isEmpty)
    }

    // MARK: - T2: 無音

    func testSilenceReportsNothingMeasurable() {
        let silence = [Float](repeating: 0, count: Int(sampleRate * 3))
        let result = analyze(channels: [silence, silence])

        XCTAssertNil(result.integratedLUFS)
        XCTAssertNil(result.maxShortTermLUFS)
        XCTAssertNil(result.samplePeakDBFS)
        XCTAssertNil(result.truePeakDBTP)
        XCTAssertEqual(result.clipRunCount, 0)
        // 無音のステレオは打ち消しの根拠がないため 1.0(モノ互換に問題なし)とする。
        XCTAssertEqual(result.stereoCorrelation ?? .nan, 1.0, accuracy: 0.0001)
    }

    // MARK: - T3: フルスケール方形波(クリップ疑い)

    func testFullScaleSquareWaveTripsClipDetection() {
        let count = Int(sampleRate)
        let square: [Float] = (0..<count).map { index in
            let phase = 2.0 * Double.pi * 1000.0 * Double(index) / sampleRate + 1e-9
            return sin(phase) >= 0 ? 1.0 : -1.0
        }
        let result = analyze(channels: [square])

        XCTAssertEqual(result.samplePeakDBFS ?? .nan, 0.0, accuracy: 0.001)
        // |x| ≥ 0.999 が信号全体で連続するため、ランは1つとして数える(ミラー一致)。
        XCTAssertEqual(result.clipRunCount, 1)
        XCTAssertEqual(result.clipRunSeconds.first ?? .nan, 0.0, accuracy: 0.001)
        // 方形波の帯域制限補間はオーバーシュートする(ミラー実測 +1.848 dBTP)。
        XCTAssertEqual(result.truePeakDBTP ?? .nan, 1.848, accuracy: 0.1)
        // ミラー実測 +0.825 LUFS。
        XCTAssertEqual(result.integratedLUFS ?? .nan, 0.825, accuracy: 0.1)
        // 1秒の音源に3秒窓は成立しない。
        XCTAssertNil(result.maxShortTermLUFS)
        XCTAssertNil(result.stereoCorrelation)
    }

    // MARK: - T4: 逆相ステレオ(モノ互換)

    func testAntiPhaseStereoReportsNegativeCorrelation() {
        let left = sine(frequency: 997, amplitude: 0.5, seconds: 5)
        let right = left.map { -$0 }
        let result = analyze(channels: [left, right])

        XCTAssertEqual(result.stereoCorrelation ?? .nan, -1.0, accuracy: 0.0001)
        // 位相はラウドネスに影響しない(各チャンネル独立に加算)。ミラー実測 -6.021。
        XCTAssertEqual(result.integratedLUFS ?? .nan, -6.021, accuracy: 0.05)
    }

    // MARK: - T5: インターサンプルピーク

    func testInterSamplePeakExceedsSamplePeak() {
        // fs/4 の正弦波を位相 π/4 でサンプリングすると、標本値は ±(A/√2) に留まり
        // 真のピーク A はサンプル間に隠れる。48タップFIRのミラー実測は -6.159 dBTP
        // (理想値 -6.021 に対する僅かな未達はフィルタ長由来で設計どおり)。
        let count = Int(sampleRate)
        let signal: [Float] = (0..<count).map { index in
            Float(0.5 * sin(2.0 * Double.pi * (sampleRate / 4.0) * Double(index) / sampleRate + Double.pi / 4.0))
        }
        let result = analyze(channels: [signal])

        XCTAssertEqual(result.samplePeakDBFS ?? .nan, -9.031, accuracy: 0.02)
        XCTAssertEqual(result.truePeakDBTP ?? .nan, -6.159, accuracy: 0.08)
        let gap = (result.truePeakDBTP ?? .nan) - (result.samplePeakDBFS ?? .nan)
        XCTAssertGreaterThan(gap, 2.5)
    }

    // MARK: - T6: チャンク分割不変性(streaming状態の持ち回り検証)

    func testChunkedProcessingMatchesWholeSignal() {
        let left = sine(frequency: 997, amplitude: 0.1, seconds: 10)
        let right = sine(frequency: 997, amplitude: 0.1, seconds: 10, phase: 0.3)

        let whole = analyze(channels: [left, right])

        let chunkedEngine = KitsunebiAnalyzerEngine(
            sampleRate: sampleRate,
            channelCount: 2,
            maximumChunkFrames: 4096
        )
        var offset = 0
        let chunkSize = 3001 // ホップ境界ともチャンク境界とも一致しない素な値
        while offset < left.count {
            let end = min(offset + chunkSize, left.count)
            chunkedEngine.process(channels: [
                Array(left[offset..<end]),
                Array(right[offset..<end]),
            ])
            offset = end
        }
        let chunked = chunkedEngine.finalize()

        XCTAssertEqual(whole.frameCount, chunked.frameCount)
        XCTAssertEqual(whole.integratedLUFS ?? .nan, chunked.integratedLUFS ?? .nan, accuracy: 0.001)
        XCTAssertEqual(whole.maxShortTermLUFS ?? .nan, chunked.maxShortTermLUFS ?? .nan, accuracy: 0.001)
        XCTAssertEqual(whole.samplePeakDBFS ?? .nan, chunked.samplePeakDBFS ?? .nan, accuracy: 0.001)
        XCTAssertEqual(whole.truePeakDBTP ?? .nan, chunked.truePeakDBTP ?? .nan, accuracy: 0.001)
        XCTAssertEqual(whole.stereoCorrelation ?? .nan, chunked.stereoCorrelation ?? .nan, accuracy: 0.0001)
        XCTAssertEqual(whole.clipRunCount, chunked.clipRunCount)
    }

    // MARK: - クリップランの境界

    func testClipRunsRequireThreeConsecutiveSamples() {
        var signal = [Float](repeating: 0, count: Int(sampleRate))
        // 2サンプルのラン(数えない)
        signal[1000] = 1.0
        signal[1001] = 1.0
        // 3サンプルのラン(数える)
        signal[2000] = -1.0
        signal[2001] = -1.0
        signal[2002] = -1.0
        // チャンク境界(4096)をまたぐ4サンプルのラン(数える)
        signal[4094] = 1.0
        signal[4095] = 1.0
        signal[4096] = 1.0
        signal[4097] = 1.0

        let result = analyze(channels: [signal], maximumChunkFrames: 4096)

        XCTAssertEqual(result.clipRunCount, 2)
        XCTAssertEqual(result.clipRunSeconds.count, 2)
        XCTAssertEqual(result.clipRunSeconds[0], 2000.0 / sampleRate, accuracy: 0.0001)
        XCTAssertEqual(result.clipRunSeconds[1], 4094.0 / sampleRate, accuracy: 0.0001)
    }

    // MARK: - キャッシュ契約

    func testTobariMetricsCacheValidation() {
        var metrics = TobariMetrics(
            analyzerVersion: TobariMetrics.currentAnalyzerVersion,
            contentHash: "abc",
            analyzedAt: Date(),
            sampleRate: 48000,
            durationSeconds: 1,
            channelCount: 2,
            integratedLUFS: -14,
            maxShortTermLUFS: -12,
            samplePeakDBFS: -1,
            truePeakDBTP: -0.5,
            clipRunCount: 0,
            clipRunSeconds: [],
            stereoCorrelation: 0.9
        )

        XCTAssertTrue(metrics.isValidCache(for: "abc"))
        XCTAssertFalse(metrics.isValidCache(for: "def"))
        XCTAssertFalse(metrics.isValidCache(for: nil))

        metrics.analyzerVersion = TobariMetrics.currentAnalyzerVersion - 1
        XCTAssertFalse(metrics.isValidCache(for: "abc"))
    }

    func testTobariMetricsSurvivesJSONRoundTrip() throws {
        let metrics = TobariMetrics(
            analyzerVersion: TobariMetrics.currentAnalyzerVersion,
            contentHash: "abc",
            analyzedAt: Date(timeIntervalSince1970: 1_000_000),
            sampleRate: 44100,
            durationSeconds: 123.4,
            channelCount: 1,
            integratedLUFS: nil,
            maxShortTermLUFS: nil,
            samplePeakDBFS: -3.2,
            truePeakDBTP: -2.9,
            clipRunCount: 4,
            clipRunSeconds: [0.5, 1.5],
            stereoCorrelation: nil
        )
        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(TobariMetrics.self, from: data)
        XCTAssertEqual(decoded, metrics)
    }

    // MARK: - 提案の根拠

    func testSuggestionsFireOnlyWithEvidence() {
        let clean = TobariMetrics(
            analyzerVersion: TobariMetrics.currentAnalyzerVersion,
            contentHash: nil,
            analyzedAt: Date(),
            sampleRate: 48000,
            durationSeconds: 60,
            channelCount: 2,
            integratedLUFS: -14,
            maxShortTermLUFS: -11,
            samplePeakDBFS: -3,
            truePeakDBTP: -1.5,
            clipRunCount: 0,
            clipRunSeconds: [],
            stereoCorrelation: 0.8
        )
        XCTAssertTrue(clean.suggestions.isEmpty)

        var hot = clean
        hot.truePeakDBTP = -0.2
        hot.clipRunCount = 3
        hot.clipRunSeconds = [1.0, 2.0, 3.0]
        hot.stereoCorrelation = -0.4
        let suggestions = hot.suggestions
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(Set(suggestions.map(\.id)), ["truePeak", "clip", "monoCompat"])
    }
}
