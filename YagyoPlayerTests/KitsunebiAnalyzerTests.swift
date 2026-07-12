import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
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

    // MARK: - T1b: EBU基準系(44.1 kHz、係数式ブランチ)

    func testReferenceSineAtFortyFourPointOne() {
        // 非48kHzはDe Man系のパラメータ化(pyloudnorm同一)で係数を再設計する。
        // ミラー実測 -19.9972 LUFS(残差は双一次変換の周波数歪みで設計どおり)。
        // 移植元のRBJ近似では -20.246 と EBU Tech 3341 の許容±0.1を外れていた。
        let sr = 44100.0
        let count = Int(sr * 10)
        let signal: [Float] = (0..<count).map { index in
            Float(0.1 * sin(2.0 * .pi * 997.0 * Double(index) / sr))
        }
        let engine = KitsunebiAnalyzerEngine(sampleRate: sr, channelCount: 2)
        engine.process(channels: [signal, signal])
        let result = engine.finalize()

        XCTAssertEqual(result.integratedLUFS ?? .nan, -20.0, accuracy: 0.05)
        XCTAssertEqual(result.maxShortTermLUFS ?? .nan, -20.0, accuracy: 0.05)
        XCTAssertEqual(result.samplePeakDBFS ?? .nan, -20.0, accuracy: 0.01)
        XCTAssertEqual(result.truePeakDBTP ?? .nan, -20.0, accuracy: 0.05)
        XCTAssertEqual(result.stereoCorrelation ?? .nan, 1.0, accuracy: 0.0001)
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
        // 位置は開始時刻の昇順で保持される契約。regression時にクラッシュではなく
        // 失敗として記録されるよう、subscriptではなく安全な取り出しで比較する。
        XCTAssertEqual(result.clipRunSeconds.first ?? .nan, 2000.0 / sampleRate, accuracy: 0.0001)
        XCTAssertEqual(
            result.clipRunSeconds.dropFirst().first ?? .nan,
            4094.0 / sampleRate,
            accuracy: 0.0001
        )
    }

    // MARK: - チャンネルレイアウト → BS.1770重み / 相関ペア

    func testChannelLayoutResolvesWeightsAndCorrelationPair() throws {
        // MPEG_5_1_D は C L R Ls Rs LFE。ラベル展開が正しければ
        // C/L/R=1.0, Ls/Rs=1.41, LFE=0、相関ペアは(L,R)=(1,2)になる。
        let layoutD = try XCTUnwrap(
            AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_D)
        )
        let formatD = AVAudioFormat(standardFormatWithSampleRate: 48000, channelLayout: layoutD)
        XCTAssertEqual(
            KitsunebiAnalyzer.channelWeights(for: formatD),
            [1.0, 1.0, 1.0, 1.41, 1.41, 0.0]
        )
        let pairD = KitsunebiAnalyzer.correlationChannels(for: formatD)
        XCTAssertEqual(pairD.0, 1)
        XCTAssertEqual(pairD.1, 2)

        // MPEG_5_1_A は L R C LFE Ls Rs。
        let layoutA = try XCTUnwrap(
            AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A)
        )
        let formatA = AVAudioFormat(standardFormatWithSampleRate: 48000, channelLayout: layoutA)
        XCTAssertEqual(
            KitsunebiAnalyzer.channelWeights(for: formatA),
            [1.0, 1.0, 1.0, 0.0, 1.41, 1.41]
        )
        let pairA = KitsunebiAnalyzer.correlationChannels(for: formatA)
        XCTAssertEqual(pairA.0, 0)
        XCTAssertEqual(pairA.1, 1)

        // ステレオは重みnil(=等重み)・先頭2ch。
        let stereo = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)
        )
        XCTAssertNil(KitsunebiAnalyzer.channelWeights(for: stereo))
        let stereoPair = KitsunebiAnalyzer.correlationChannels(for: stereo)
        XCTAssertEqual(stereoPair.0, 0)
        XCTAssertEqual(stereoPair.1, 1)

        // ビットマップ形式(マルチチャンネルWAVのチャンネルマスク)も展開できる。
        // ビット順の展開は L R C LFE Ls Rs。
        var bitmapLayout = AudioChannelLayout()
        bitmapLayout.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelBitmap
        bitmapLayout.mChannelBitmap = AudioChannelBitmap([
            .bit_Left, .bit_Right, .bit_Center, .bit_LFEScreen,
            .bit_LeftSurround, .bit_RightSurround,
        ])
        let bitmapFormat = withUnsafePointer(to: bitmapLayout) { pointer in
            AVAudioFormat(
                standardFormatWithSampleRate: 48000,
                channelLayout: AVAudioChannelLayout(layout: pointer)
            )
        }
        XCTAssertEqual(
            KitsunebiAnalyzer.channelWeights(for: bitmapFormat),
            [1.0, 1.0, 1.0, 0.0, 1.41, 1.41]
        )
    }

    func testCorrelationUsesResolvedChannels() {
        // 3ch構成で「実際のL/R」が(1,2)にある場合: ch0(=C相当)は無音でも
        // 逆相のL/Rから相関-1.0を検出できる。先頭2ch決め打ちだと0除算→1.0側に落ちる。
        let left = sine(frequency: 997, amplitude: 0.5, seconds: 2)
        let right = left.map { -$0 }
        let center = [Float](repeating: 0, count: left.count)

        let engine = KitsunebiAnalyzerEngine(
            sampleRate: sampleRate,
            channelCount: 3,
            correlationChannels: (1, 2)
        )
        center.withUnsafeBufferPointer { c in
            left.withUnsafeBufferPointer { l in
                right.withUnsafeBufferPointer { r in
                    engine.process(
                        channelPointers: [c.baseAddress!, l.baseAddress!, r.baseAddress!],
                        frameCount: left.count
                    )
                }
            }
        }
        let result = engine.finalize()
        XCTAssertEqual(result.stereoCorrelation ?? .nan, -1.0, accuracy: 0.0001)
    }

    // MARK: - ファイル経由のE2E(AVAudioFile読み取り経路)

    func testAnalyzeFileEndToEnd() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tobari-e2e-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            XCTFail("フォーマットを作成できません")
            return
        }
        let signal = sine(frequency: 997, amplitude: 0.1, seconds: 4)
        do {
            // 書き込み側のAVAudioFileはスコープを抜けた時点で確定させる。
            let file = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(signal.count)
            ), let channelData = buffer.floatChannelData else {
                XCTFail("書き込みバッファを確保できません")
                return
            }
            for channel in 0..<2 {
                signal.withUnsafeBufferPointer { pointer in
                    channelData[channel].update(from: pointer.baseAddress!, count: signal.count)
                }
            }
            buffer.frameLength = AVAudioFrameCount(signal.count)
            try file.write(from: buffer)
        }

        final class ProgressRecorder: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [Double] = []
            func record(_ value: Double) {
                lock.lock()
                values.append(value)
                lock.unlock()
            }
            var last: Double? {
                lock.lock()
                defer { lock.unlock() }
                return values.last
            }
            var isMonotonic: Bool {
                lock.lock()
                defer { lock.unlock() }
                return zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
            }
        }
        let recorder = ProgressRecorder()

        let result = try KitsunebiAnalyzer.analyze(url: url) { fraction in
            recorder.record(fraction)
        }

        // EBU基準系がファイル読み(chunked)経由でも成立する。
        XCTAssertEqual(result.frameCount, signal.count)
        XCTAssertEqual(result.integratedLUFS ?? .nan, -20.0, accuracy: 0.05)
        XCTAssertEqual(result.maxShortTermLUFS ?? .nan, -20.0, accuracy: 0.05)
        XCTAssertEqual(result.samplePeakDBFS ?? .nan, -20.0, accuracy: 0.02)
        XCTAssertEqual(result.stereoCorrelation ?? .nan, 1.0, accuracy: 0.0001)
        XCTAssertEqual(recorder.last ?? .nan, 1.0, accuracy: 0.0001)
        XCTAssertTrue(recorder.isMonotonic)
    }

    // MARK: - QA artifact(帳の一画面)

    @MainActor
    func testExportsTobariScreenArtifact() throws {
        // 提案3種がすべて出る代表値で帳を描き、PNGをxcresultへ添付する
        // (ParadeQAArtifactTestsと同じ証跡パターン)。
        let metrics = TobariMetrics(
            analyzerVersion: TobariMetrics.currentAnalyzerVersion,
            contentHash: "artifact-sample",
            analyzedAt: Date(timeIntervalSince1970: 1_784_000_000),
            sampleRate: 48000,
            durationSeconds: 217,
            channelCount: 2,
            integratedLUFS: -12.4,
            maxShortTermLUFS: -9.8,
            samplePeakDBFS: -0.31,
            truePeakDBTP: 0.12,
            clipRunCount: 2,
            clipRunSeconds: [63.2, 148.7],
            stereoCorrelation: 0.14
        )
        let track = AudioTrack(
            title: "宵の底 (rough mix 3)",
            originalFilename: "yoinosoko.wav",
            storedFilename: "yoinosoko.caf",
            artist: "tinypony"
        )
        let store = AudioLibraryStore(
            documentsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("tobari-artifact-\(UUID().uuidString)", isDirectory: true)
        )
        let view = TobariView(track: track, presetMetrics: metrics)
            .environmentObject(store)

        // 撮影は共通ヘルパー(WindowArtifactExporter)で行う。
        try exportWindowArtifact(rootView: view, attachmentName: "tobari-screen.png")
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

        // 自身のhashがnil(backfill不能で表示のみだった結果)はキャッシュとして無効。
        metrics.analyzerVersion = TobariMetrics.currentAnalyzerVersion
        metrics.contentHash = nil
        XCTAssertFalse(metrics.isValidCache(for: "abc"))
        XCTAssertFalse(metrics.isValidCache(for: nil))
    }

    func testMonoCompatTextDistinguishesMonoFromUnmeasurable() {
        var metrics = TobariMetrics(
            analyzerVersion: TobariMetrics.currentAnalyzerVersion,
            contentHash: nil,
            analyzedAt: Date(),
            sampleRate: 48000,
            durationSeconds: 1,
            channelCount: 1,
            integratedLUFS: nil,
            maxShortTermLUFS: nil,
            samplePeakDBFS: nil,
            truePeakDBTP: nil,
            clipRunCount: 0,
            clipRunSeconds: [],
            stereoCorrelation: nil
        )
        XCTAssertEqual(metrics.monoCompatText, "モノラル音源")
        // ステレオで相関が計測不能(壊れたサンプル)の場合はモノラルと区別する。
        metrics.channelCount = 2
        XCTAssertEqual(metrics.monoCompatText, "計測不能")
        metrics.stereoCorrelation = 0.87
        XCTAssertEqual(metrics.monoCompatText, "0.87")
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
        hot.truePeakDBTP = 0.4
        hot.clipRunCount = 3
        hot.clipRunSeconds = [1.0, 2.0, 3.0]
        hot.stereoCorrelation = -0.4
        let suggestions = hot.suggestions
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(Set(suggestions.map(\.id)), ["truePeak", "clip", "monoCompat"])

        // -1.0〜0 dBTPの帯はマスター段階で気にしない(作者判断 2026-07-13):
        // ロスレス再生は0 dBTPまで問題なく、配信プラットフォームは
        // ノーマライズ時にTrue Peak側も面倒を見る。提案は0 dBTP超のみ。
        var streamingLoud = clean
        streamingLoud.truePeakDBTP = -0.2
        XCTAssertTrue(streamingLoud.suggestions.isEmpty)
    }
}
