import Accelerate
import AudioToolbox
import AVFoundation

/// 狐火の帳(Step 5 Phase A)のオフライン解析。
/// Mastering-App の `KWeightingFilter` / `LUFSMeter` / `TruePeakMeter` /
/// `AudioAnalyzer` の streaming 手法を移植・補修したもので、
/// 全指標を1パスの chunked 読みで算出する(仕様: 2026-07-12-kitsunebi-no-tobari-design.md)。
/// 再生経路には依存せず、読み取り専用・非破壊で動く。

/// 解析の生の計測結果。`TobariMetrics` へは呼び出し側が
/// contentHash / analyzedAt を添えて変換する。
struct TobariMeasurement: Sendable {
    var sampleRate: Double
    var channelCount: Int
    var frameCount: Int
    var integratedLUFS: Double?
    var maxShortTermLUFS: Double?
    var samplePeakDBFS: Double?
    var truePeakDBTP: Double?
    var clipRunCount: Int
    var clipRunSeconds: [Double]
    /// nil はモノラル音源。
    var stereoCorrelation: Double?

    var durationSeconds: Double {
        sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }
}

enum TobariAnalysisError: LocalizedError {
    case unreadableFile(String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case let .unreadableFile(reason):
            return "音源を読み込めませんでした: \(reason)"
        case let .unsupportedFormat(reason):
            return "解析できない形式です: \(reason)"
        }
    }
}

/// ITU-R BS.1770-4 の K-weighting バイクアッド係数。48 kHz は Table 1/2 の公式係数、
/// それ以外はDe Man系のパラメータ化(pyloudnormと同一)で再設計する。
/// この式は fs=48000 を代入すると公式係数を機械精度で再現する
/// (移植元のRBJ cookbook近似は44.1 kHzで-0.25 LUずれるためレビューで差し替えた)。
enum KWeightingCoefficients {
    /// Stage 1: Pre-filter(High Shelf, +4 dB @ 1681 Hz)。[b0, b1, b2, a1, a2]
    static func stage1(sampleRate: Double) -> [Float] {
        if sampleRate == 48000 {
            return [1.53512485958697, -2.69169618940638, 1.19839281085285,
                    -1.69065929318241, 0.73248077421585]
        }
        let frequency = 1681.974450955533
        let gainDB = 3.999843853973347
        let q = 0.7071752369554196
        let k = tan(Double.pi * frequency / sampleRate)
        let vh = pow(10.0, gainDB / 20.0)
        let vb = pow(vh, 0.4996667741545416)
        let a0 = 1.0 + k / q + k * k
        let b0 = (vh + vb * k / q + k * k) / a0
        let b1 = 2.0 * (k * k - vh) / a0
        let b2 = (vh - vb * k / q + k * k) / a0
        let a1 = 2.0 * (k * k - 1.0) / a0
        let a2 = (1.0 - k / q + k * k) / a0
        return [Float(b0), Float(b1), Float(b2), Float(a1), Float(a2)]
    }

    /// Stage 2: RLB weighting(High Pass, 38 Hz)。[b0, b1, b2, a1, a2]
    /// 分子は正規化しない [1, -2, 1](公式表と同じく通過帯域+0.03 dBを保つ)。
    static func stage2(sampleRate: Double) -> [Float] {
        if sampleRate == 48000 {
            return [1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621]
        }
        let frequency = 38.13547087602444
        let q = 0.5003270373238773
        let k = tan(Double.pi * frequency / sampleRate)
        let denominator = 1.0 + k / q + k * k
        let a1 = 2.0 * (k * k - 1.0) / denominator
        let a2 = (1.0 - k / q + k * k) / denominator
        return [1.0, -2.0, 1.0, Float(a1), Float(a2)]
    }
}

/// 1パス streaming 解析エンジン。チャンクを順に与えて `finalize()` で全指標を得る。
/// ファイルI/Oを持たないため、テストは合成信号を直接流せる。
final class KitsunebiAnalyzerEngine {
    // MARK: - 契約定数

    /// クリップ疑いの振幅閾値。
    static let clipThreshold: Float = 0.999
    /// クリップ疑いと数える最小連続サンプル数。
    static let clipRunMinimumLength = 3
    /// 記録するクリップ位置の上限。
    static let maxClipPositions = 8
    /// True Peak のオーバーサンプリング倍率(ITU推奨 4x)。
    static let oversampleFactor = 4
    /// True Peak 補間FIRのタップ数。
    static let firTapCount = 48

    // MARK: - 構成

    private let sampleRate: Double
    private let channelCount: Int
    private let maximumChunkFrames: Int
    /// 100 ms ホップのサンプル数。
    private let hopSize: Int
    /// 400 ms ブロック = 4 ホップ(75% オーバーラップ)。
    private let hopsPerBlock = 4
    /// Short-term 3 秒 = 30 ホップ。
    private let hopsPerShortTerm = 30
    private let channelWeights: [Float]
    /// モノ互換の相関に使う実際のL/R(レイアウトで先頭2chがL/Rでない場合がある)。
    private let correlationLeftChannel: Int
    private let correlationRightChannel: Int
    private let stage1Coefficients: [Float]
    private let stage2Coefficients: [Float]
    private let firFilter: [Float]

    // MARK: - チャンネル別状態

    private struct BiquadState {
        var inputHistory: (Float, Float) = (0, 0)
        var outputHistory: (Float, Float) = (0, 0)
    }

    private var stage1States: [BiquadState]
    private var stage2States: [BiquadState]
    /// True Peak 畳み込みのオーバーラップ末尾(4x領域、タップ-1 サンプル)。
    /// ゼロ初期化しておくことで出力が 'full' 畳み込みと一致する。
    private var truePeakTails: [[Float]]
    private var channelTruePeakLinear: [Float]
    private var clipRunLengths: [Int]
    private var clipRunStartFrames: [Int]

    // MARK: - 全体状態

    private var samplePeakLinear: Float = 0
    private var clipRunCount = 0
    private var clipRunSecondsHead: [Double] = []
    private var dotLR: Double = 0
    private var sumL2: Double = 0
    private var sumR2: Double = 0
    private var totalFrames = 0
    private var finalized = false

    // MARK: - ラウドネス集計状態

    private var samplesInCurrentHop = 0
    private var currentHopSumSquares: Double = 0
    private var hopRingBlock: [Double]
    private var hopRingBlockIndex = 0
    private var hopRingBlockFilled = 0
    private var hopRingBlockSum: Double = 0
    private var hopRingShort: [Double]
    private var hopRingShortIndex = 0
    private var hopRingShortFilled = 0
    private var hopRingShortSum: Double = 0
    private var blockLoudnessDB: [Double] = []
    private var maxShortTermDB = -Double.infinity

    // MARK: - 作業バッファ(チャンク間で再利用)

    private var filteredChannel: [Float]
    private var squaredChannel: [Float]
    private var framePowerSums: [Float]
    private var paddedInput: [Float]
    private var paddedOutput: [Float]
    private var upsampledWithTail: [Float]
    private var convolutionOutput: [Float]

    /// - Parameters:
    ///   - channelWeights: BS.1770のチャンネル重み。nil なら全チャンネル 1.0
    ///     (モノラル/ステレオはこれが正式値。レイアウト不明の多チャンネルも、
    ///     決め打ちでチャンネルを落とすより等重みで全て数える方を選ぶ)。
    ///     ファイル入口が `KitsunebiAnalyzer.channelWeights(for:)` でラベルから解決する。
    ///   - correlationChannels: モノ互換の相関に使う2チャンネルのインデックス。
    ///     nil なら先頭2ch。レイアウトで実際のL/Rが先頭でない場合に入口が指定する。
    init(
        sampleRate: Double,
        channelCount: Int,
        maximumChunkFrames: Int = 65536,
        channelWeights: [Float]? = nil,
        correlationChannels: (Int, Int)? = nil
    ) {
        precondition(sampleRate > 0, "sampleRate must be positive")
        precondition(channelCount > 0, "channelCount must be positive")
        precondition(maximumChunkFrames > 0, "maximumChunkFrames must be positive")
        precondition(
            channelWeights == nil || channelWeights?.count == channelCount,
            "channelWeights count mismatch"
        )
        let correlationPair = correlationChannels ?? (0, 1)
        precondition(
            channelCount < 2 || (
                correlationPair.0 >= 0 && correlationPair.0 < channelCount
                && correlationPair.1 >= 0 && correlationPair.1 < channelCount
                && correlationPair.0 != correlationPair.1
            ),
            "correlationChannels out of range"
        )

        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.maximumChunkFrames = maximumChunkFrames
        self.hopSize = max(1, Int(sampleRate * 0.1))
        self.channelWeights = channelWeights ?? Array(repeating: 1.0, count: channelCount)
        self.correlationLeftChannel = correlationPair.0
        self.correlationRightChannel = correlationPair.1
        self.stage1Coefficients = KWeightingCoefficients.stage1(sampleRate: sampleRate)
        self.stage2Coefficients = KWeightingCoefficients.stage2(sampleRate: sampleRate)
        self.firFilter = Self.makeInterpolationFIR()

        self.stage1States = Array(repeating: BiquadState(), count: channelCount)
        self.stage2States = Array(repeating: BiquadState(), count: channelCount)
        self.truePeakTails = Array(
            repeating: [Float](repeating: 0, count: Self.firTapCount - 1),
            count: channelCount
        )
        self.channelTruePeakLinear = Array(repeating: 0, count: channelCount)
        self.clipRunLengths = Array(repeating: 0, count: channelCount)
        self.clipRunStartFrames = Array(repeating: 0, count: channelCount)

        self.hopRingBlock = Array(repeating: 0, count: hopsPerBlock)
        self.hopRingShort = Array(repeating: 0, count: hopsPerShortTerm)

        self.filteredChannel = Array(repeating: 0, count: maximumChunkFrames)
        self.squaredChannel = Array(repeating: 0, count: maximumChunkFrames)
        self.framePowerSums = Array(repeating: 0, count: maximumChunkFrames)
        self.paddedInput = Array(repeating: 0, count: maximumChunkFrames + 2)
        self.paddedOutput = Array(repeating: 0, count: maximumChunkFrames + 2)
        // finalize() のフラッシュ入力(FIR遅延ぶんのゼロ)も同じバッファを通るため、
        // 極端に小さい maximumChunkFrames でも溢れないよう下限を確保する。
        let flushFrames = (Self.firTapCount + Self.oversampleFactor - 1) / Self.oversampleFactor
        let maxUpsampled = max(maximumChunkFrames, flushFrames) * Self.oversampleFactor
        self.upsampledWithTail = Array(repeating: 0, count: maxUpsampled + Self.firTapCount - 1)
        self.convolutionOutput = Array(repeating: 0, count: maxUpsampled)
    }

    // MARK: - 入力

    /// チャンクを処理する。`channelPointers` は非インターリーブの各チャンネル先頭。
    /// `maximumChunkFrames` を超える入力は内部で分割される。
    func process(channelPointers: [UnsafePointer<Float>], frameCount: Int) {
        precondition(!finalized, "finalize() 後の process は不可")
        precondition(channelPointers.count == channelCount, "channel count mismatch")
        guard frameCount > 0 else { return }

        var offset = 0
        while offset < frameCount {
            let n = min(maximumChunkFrames, frameCount - offset)
            processSubChunk(channelPointers: channelPointers, offset: offset, frameCount: n)
            offset += n
        }
    }

    /// テスト用の便宜API(1ch/2ch)。
    func process(channels: [[Float]]) {
        precondition(channels.count == channelCount, "channel count mismatch")
        guard let frameCount = channels.first?.count, frameCount > 0 else { return }
        precondition(channels.allSatisfy { $0.count == frameCount }, "ragged channels")

        switch channels.count {
        case 1:
            channels[0].withUnsafeBufferPointer { c0 in
                process(channelPointers: [c0.baseAddress!], frameCount: frameCount)
            }
        case 2:
            channels[0].withUnsafeBufferPointer { c0 in
                channels[1].withUnsafeBufferPointer { c1 in
                    process(
                        channelPointers: [c0.baseAddress!, c1.baseAddress!],
                        frameCount: frameCount
                    )
                }
            }
        default:
            preconditionFailure("process(channels:) は1ch/2chのテスト専用")
        }
    }

    private func processSubChunk(
        channelPointers: [UnsafePointer<Float>],
        offset: Int,
        frameCount n: Int
    ) {
        framePowerSums.withUnsafeMutableBufferPointer { power in
            vDSP_vclr(power.baseAddress!, 1, vDSP_Length(n))
        }

        for channel in 0..<channelCount {
            let raw = channelPointers[channel] + offset

            // サンプルピーク(生信号)
            var chunkMax: Float = 0
            vDSP_maxmgv(raw, 1, &chunkMax, vDSP_Length(n))
            samplePeakLinear = max(samplePeakLinear, chunkMax)

            // クリップ疑い: 連続ランをチャンク越しに追跡する(生信号)
            scanClipRuns(raw: raw, frameCount: n, channel: channel)

            // True Peak: 4x ゼロスタッフィング + FIR(生信号)
            accumulateTruePeak(raw: raw, frameCount: n, channel: channel)

            // K-weighting 2段(作業バッファへコピーしてから)
            filteredChannel.withUnsafeMutableBufferPointer { filtered in
                filtered.baseAddress!.update(from: raw, count: n)
            }
            applyStreamingBiquad(
                sampleCount: n, coefficients: stage1Coefficients, state: &stage1States[channel]
            )
            applyStreamingBiquad(
                sampleCount: n, coefficients: stage2Coefficients, state: &stage2States[channel]
            )

            // チャンネル重み付きの二乗を全チャンネル合算パワーへ加える
            filteredChannel.withUnsafeBufferPointer { filtered in
                squaredChannel.withUnsafeMutableBufferPointer { squared in
                    vDSP_vsq(filtered.baseAddress!, 1, squared.baseAddress!, 1, vDSP_Length(n))
                }
            }
            var weight = channelWeights[channel]
            squaredChannel.withUnsafeBufferPointer { squared in
                framePowerSums.withUnsafeMutableBufferPointer { power in
                    vDSP_vsma(
                        squared.baseAddress!, 1, &weight,
                        power.baseAddress!, 1,
                        power.baseAddress!, 1,
                        vDSP_Length(n)
                    )
                }
            }
        }

        // 位相相関(レイアウトから解決した実際のL/R。既定は先頭2ch)
        if channelCount >= 2 {
            let left = channelPointers[correlationLeftChannel] + offset
            let right = channelPointers[correlationRightChannel] + offset
            var dot: Float = 0
            var l2: Float = 0
            var r2: Float = 0
            vDSP_dotpr(left, 1, right, 1, &dot, vDSP_Length(n))
            vDSP_dotpr(left, 1, left, 1, &l2, vDSP_Length(n))
            vDSP_dotpr(right, 1, right, 1, &r2, vDSP_Length(n))
            dotLR += Double(dot)
            sumL2 += Double(l2)
            sumR2 += Double(r2)
        }

        accumulateLoudnessHops(frameCount: n)
        totalFrames += n
    }

    // MARK: - K-weighting(streaming biquad、vDSP_deq22)

    private func applyStreamingBiquad(
        sampleCount n: Int,
        coefficients: [Float],
        state: inout BiquadState
    ) {
        paddedInput[0] = state.inputHistory.0
        paddedInput[1] = state.inputHistory.1
        paddedOutput[0] = state.outputHistory.0
        paddedOutput[1] = state.outputHistory.1
        filteredChannel.withUnsafeBufferPointer { filtered in
            paddedInput.withUnsafeMutableBufferPointer { padded in
                (padded.baseAddress! + 2).update(from: filtered.baseAddress!, count: n)
            }
        }
        var localCoefficients = coefficients
        vDSP_deq22(&paddedInput, 1, &localCoefficients, &paddedOutput, 1, vDSP_Length(n))
        paddedOutput.withUnsafeBufferPointer { padded in
            filteredChannel.withUnsafeMutableBufferPointer { filtered in
                filtered.baseAddress!.update(from: padded.baseAddress! + 2, count: n)
            }
        }
        state.inputHistory = (paddedInput[n], paddedInput[n + 1])
        state.outputHistory = (paddedOutput[n], paddedOutput[n + 1])
    }

    // MARK: - クリップ疑い

    private func scanClipRuns(raw: UnsafePointer<Float>, frameCount n: Int, channel: Int) {
        var runLength = clipRunLengths[channel]
        var runStart = clipRunStartFrames[channel]
        for index in 0..<n {
            if abs(raw[index]) >= Self.clipThreshold {
                if runLength == 0 {
                    runStart = totalFrames + index
                }
                runLength += 1
            } else if runLength > 0 {
                registerClipRun(length: runLength, startFrame: runStart)
                runLength = 0
            }
        }
        clipRunLengths[channel] = runLength
        clipRunStartFrames[channel] = runStart
    }

    private func registerClipRun(length: Int, startFrame: Int) {
        guard length >= Self.clipRunMinimumLength else { return }
        clipRunCount += 1
        // 「先頭から最大8件」の契約: 登録はチャンク×チャンネル順に届くため、
        // 到着順ではなく開始時刻が小さい8件を保持する(常に昇順)。
        let seconds = Double(startFrame) / sampleRate
        if clipRunSecondsHead.count < Self.maxClipPositions {
            clipRunSecondsHead.append(seconds)
            clipRunSecondsHead.sort()
        } else if let latest = clipRunSecondsHead.last, seconds < latest {
            clipRunSecondsHead[Self.maxClipPositions - 1] = seconds
            clipRunSecondsHead.sort()
        }
    }

    // MARK: - True Peak(4x FIR 補間、チャンク越しオーバーラップ)

    private func accumulateTruePeak(raw: UnsafePointer<Float>, frameCount n: Int, channel: Int) {
        let tapCount = Self.firTapCount
        let factor = Self.oversampleFactor
        let upsampledCount = n * factor
        let tailCount = tapCount - 1

        // 先頭に前回末尾(初期はゼロ)を置き、続きへ4xゼロスタッフィングする
        truePeakTails[channel].withUnsafeBufferPointer { tail in
            upsampledWithTail.withUnsafeMutableBufferPointer { buffer in
                buffer.baseAddress!.update(from: tail.baseAddress!, count: tailCount)
                vDSP_vclr(buffer.baseAddress! + tailCount, 1, vDSP_Length(upsampledCount))
                for index in 0..<n {
                    buffer.baseAddress![tailCount + index * factor] = raw[index]
                }
            }
        }

        let totalCount = tailCount + upsampledCount
        let outputCount = totalCount - tapCount + 1
        guard outputCount > 0 else {
            saveTruePeakTail(channel: channel, totalCount: totalCount)
            return
        }

        var chunkPeak: Float = 0
        firFilter.withUnsafeBufferPointer { fir in
            upsampledWithTail.withUnsafeBufferPointer { buffer in
                convolutionOutput.withUnsafeMutableBufferPointer { output in
                    vDSP_conv(
                        buffer.baseAddress!, 1,
                        fir.baseAddress! + tapCount - 1, -1,
                        output.baseAddress!, 1,
                        vDSP_Length(outputCount),
                        vDSP_Length(tapCount)
                    )
                    vDSP_maxmgv(output.baseAddress!, 1, &chunkPeak, vDSP_Length(outputCount))
                }
            }
        }
        channelTruePeakLinear[channel] = max(channelTruePeakLinear[channel], chunkPeak)
        saveTruePeakTail(channel: channel, totalCount: totalCount)
    }

    private func saveTruePeakTail(channel: Int, totalCount: Int) {
        let tailCount = Self.firTapCount - 1
        let keep = min(tailCount, totalCount)
        let start = totalCount - keep
        truePeakTails[channel].withUnsafeMutableBufferPointer { tail in
            upsampledWithTail.withUnsafeBufferPointer { buffer in
                if keep < tailCount {
                    vDSP_vclr(tail.baseAddress!, 1, vDSP_Length(tailCount - keep))
                }
                (tail.baseAddress! + (tailCount - keep))
                    .update(from: buffer.baseAddress! + start, count: keep)
            }
        }
    }

    // MARK: - ラウドネス(100msホップ → 400msブロック / 3秒Short-term)

    private func accumulateLoudnessHops(frameCount n: Int) {
        var chunkOffset = 0
        while chunkOffset < n {
            let requiredForHop = hopSize - samplesInCurrentHop
            let segmentLength = min(requiredForHop, n - chunkOffset)
            var segmentSum: Float = 0
            framePowerSums.withUnsafeBufferPointer { power in
                vDSP_sve(power.baseAddress! + chunkOffset, 1, &segmentSum, vDSP_Length(segmentLength))
            }
            currentHopSumSquares += Double(segmentSum)
            samplesInCurrentHop += segmentLength
            chunkOffset += segmentLength

            if samplesInCurrentHop >= hopSize {
                commitHop(meanSquare: currentHopSumSquares / Double(hopSize))
                currentHopSumSquares = 0
                samplesInCurrentHop = 0
            }
        }
    }

    private func commitHop(meanSquare: Double) {
        // 400msブロック(momentary)リング
        if hopRingBlockFilled < hopsPerBlock {
            hopRingBlock[hopRingBlockIndex] = meanSquare
            hopRingBlockSum += meanSquare
            hopRingBlockFilled += 1
        } else {
            hopRingBlockSum -= hopRingBlock[hopRingBlockIndex]
            hopRingBlock[hopRingBlockIndex] = meanSquare
            hopRingBlockSum += meanSquare
        }
        hopRingBlockIndex = (hopRingBlockIndex + 1) % hopsPerBlock
        if hopRingBlockFilled == hopsPerBlock {
            blockLoudnessDB.append(loudnessDB(meanSquare: hopRingBlockSum / Double(hopsPerBlock)))
        }

        // 3秒Short-termリング(補修1: streaming化)
        if hopRingShortFilled < hopsPerShortTerm {
            hopRingShort[hopRingShortIndex] = meanSquare
            hopRingShortSum += meanSquare
            hopRingShortFilled += 1
        } else {
            hopRingShortSum -= hopRingShort[hopRingShortIndex]
            hopRingShort[hopRingShortIndex] = meanSquare
            hopRingShortSum += meanSquare
        }
        hopRingShortIndex = (hopRingShortIndex + 1) % hopsPerShortTerm
        if hopRingShortFilled == hopsPerShortTerm {
            let shortTerm = loudnessDB(meanSquare: hopRingShortSum / Double(hopsPerShortTerm))
            maxShortTermDB = max(maxShortTermDB, shortTerm)
        }
    }

    private func loudnessDB(meanSquare: Double) -> Double {
        meanSquare > 0 ? -0.691 + 10.0 * log10(meanSquare) : -Double.infinity
    }

    // MARK: - 確定

    func finalize() -> TobariMeasurement {
        precondition(!finalized, "finalize() は一度だけ")
        finalized = true

        // True Peak の末尾フラッシュ: FIR遅延ぶんのゼロ入力で残り出力を得る
        let flushFrames = (Self.firTapCount + Self.oversampleFactor - 1) / Self.oversampleFactor
        let zeros = [Float](repeating: 0, count: flushFrames)
        for channel in 0..<channelCount {
            zeros.withUnsafeBufferPointer { pointer in
                accumulateTruePeak(raw: pointer.baseAddress!, frameCount: flushFrames, channel: channel)
            }
            // 途中で終わったクリップランを確定する
            registerClipRun(
                length: clipRunLengths[channel],
                startFrame: clipRunStartFrames[channel]
            )
            clipRunLengths[channel] = 0
        }

        // Integrated: 絶対ゲート(-70) → 相対ゲート(平均-10) → パワー平均
        let absoluteGated = blockLoudnessDB.filter { $0.isFinite && $0 > -70.0 }
        var integrated: Double?
        if !absoluteGated.isEmpty {
            let relativeThreshold = powerMeanDB(absoluteGated) - 10.0
            let relativeGated = absoluteGated.filter { $0 > relativeThreshold }
            if !relativeGated.isEmpty {
                integrated = powerMeanDB(relativeGated)
            }
        }

        let truePeakLinear = channelTruePeakLinear.max() ?? 0
        let stereoCorrelation: Double?
        if channelCount >= 2 {
            let denominator = (sumL2 * sumR2).squareRoot()
            if denominator == 0 {
                // 無音のステレオ: 打ち消しの根拠がないため 1.0(モノ互換に問題なし)。
                stereoCorrelation = 1.0
            } else if denominator.isFinite {
                // 正常系でも丸めで±1をわずかに越え得るためクランプする。
                let raw = dotLR / denominator
                stereoCorrelation = raw.isFinite ? min(1.0, max(-1.0, raw)) : nil
            } else {
                // 壊れたサンプル(±inf/NaN)で累積が溢れた場合は計測不能。
                // 0や偽の負値を出して誤った警告を誘発しない。
                stereoCorrelation = nil
            }
        } else {
            stereoCorrelation = nil
        }

        return TobariMeasurement(
            sampleRate: sampleRate,
            channelCount: channelCount,
            frameCount: totalFrames,
            integratedLUFS: integrated,
            maxShortTermLUFS: maxShortTermDB.isFinite ? maxShortTermDB : nil,
            samplePeakDBFS: finiteDB(linear: samplePeakLinear),
            truePeakDBTP: finiteDB(linear: truePeakLinear),
            clipRunCount: clipRunCount,
            clipRunSeconds: clipRunSecondsHead,
            stereoCorrelation: stereoCorrelation
        )
    }

    /// 線形振幅をdBへ。無音(0)や壊れたサンプル由来の非有限値はnil(計測不能)にし、
    /// 非有限値がJSONや表示へ漏れない契約を守る。
    private func finiteDB(linear: Float) -> Double? {
        guard linear > 0, linear.isFinite else { return nil }
        let db = 20.0 * log10(Double(linear))
        return db.isFinite ? db : nil
    }

    private func powerMeanDB(_ valuesDB: [Double]) -> Double {
        let meanPower = valuesDB
            .map { pow(10.0, $0 / 10.0) }
            .reduce(0.0, +) / Double(valuesDB.count)
        return 10.0 * log10(meanPower)
    }

    // MARK: - FIR 設計(Mastering-App TruePeakMeter 移植)

    /// 4x補間用ローパスFIR。sinc × 4項Blackman-Harris窓、polyphase各相DCゲイン正規化。
    private static func makeInterpolationFIR() -> [Float] {
        let taps = firTapCount
        let factor = oversampleFactor
        let cutoff = 1.0 / Float(factor)
        let gain = Float(factor)
        var coefficients = [Float](repeating: 0, count: taps)
        let center = Float(taps - 1) / 2.0
        let a0: Float = 0.35875
        let a1: Float = 0.48829
        let a2: Float = 0.14128
        let a3: Float = 0.01168

        for index in 0..<taps {
            let n = Float(index) - center
            let sinc: Float = abs(n) < 1e-6
                ? cutoff
                : sin(.pi * cutoff * n) / (.pi * n)
            let phase = 2.0 * Float.pi * Float(index) / Float(taps - 1)
            let window = a0 - a1 * cos(phase) + a2 * cos(2.0 * phase) - a3 * cos(3.0 * phase)
            coefficients[index] = sinc * window * gain
        }

        for phaseIndex in 0..<factor {
            var phaseGain: Float = 0
            var tapIndex = phaseIndex
            while tapIndex < taps {
                phaseGain += coefficients[tapIndex]
                tapIndex += factor
            }
            guard abs(phaseGain) > 1e-8 else { continue }
            let normalizer = 1.0 / phaseGain
            tapIndex = phaseIndex
            while tapIndex < taps {
                coefficients[tapIndex] *= normalizer
                tapIndex += factor
            }
        }
        return coefficients
    }
}

/// ファイルを chunked に読み、エンジンへ流す入口。
enum KitsunebiAnalyzer {
    static let readBufferFrames: AVAudioFrameCount = 65536

    /// BS.1770-4 のチャンネル重みをレイアウトから解決する。
    /// タグ決め打ちではなくチャンネルラベル(タグはAudioToolboxで展開)から導くため、
    /// MPEG/AAC/AudioUnit等どの5.1タグ順序でもLFE除外・サラウンド1.41が正しく載る。
    /// ラベルが得られない多チャンネルは nil(=等重み)で、チャンネルを黙って落とさない。
    static func channelWeights(for format: AVAudioFormat) -> [Float]? {
        guard format.channelCount > 2,
              let labels = channelLabels(for: format),
              labels.count == Int(format.channelCount),
              labels.allSatisfy({ $0 != kAudioChannelLabel_Unknown }) else {
            return nil
        }
        // BS.1770-4のブースト帯は|方位角|60°〜120°(libebur128の写像と同じ):
        // ±110(Ls/Rs)・±90(SL/SR)・±60(Lw/Rw)は1.41、±135のリアは1.0のまま。
        return labels.map { label -> Float in
            switch label {
            case kAudioChannelLabel_LFEScreen, kAudioChannelLabel_LFE2:
                return 0.0
            case kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround,
                 kAudioChannelLabel_LeftSurroundDirect, kAudioChannelLabel_RightSurroundDirect,
                 kAudioChannelLabel_LeftWide, kAudioChannelLabel_RightWide:
                return 1.41
            default:
                return 1.0
            }
        }
    }

    /// モノ互換の相関に使う実際のL/Rのインデックス。レイアウトからLeft/Rightラベルを
    /// 探し(例: MPEG_5_1_DはC,L,R,…なので(1,2))、判別できなければ先頭2ch。
    /// 相関は対称なので順序自体は結果へ影響しない。
    static func correlationChannels(for format: AVAudioFormat) -> (Int, Int) {
        guard format.channelCount > 2,
              let labels = channelLabels(for: format),
              let left = labels.firstIndex(of: kAudioChannelLabel_Left),
              let right = labels.firstIndex(of: kAudioChannelLabel_Right),
              left != right else {
            return (0, 1)
        }
        return (left, right)
    }

    /// レイアウトからチャンネルラベル列を得る。descriptions直持ちはそのまま読み、
    /// タグ/ビットマップ形式は AudioToolbox でラベル列へ展開する。
    private static func channelLabels(for format: AVAudioFormat) -> [AudioChannelLabel]? {
        guard let layout = format.channelLayout else { return nil }
        let pointer = layout.layout
        let tag = pointer.pointee.mChannelLayoutTag
        if tag == kAudioChannelLayoutTag_UseChannelDescriptions {
            return labels(from: pointer)
        }
        if tag == kAudioChannelLayoutTag_UseChannelBitmap {
            var bitmap = pointer.pointee.mChannelBitmap
            return expandedLabels(property: kAudioFormatProperty_ChannelLayoutForBitmap, specifier: &bitmap)
        }
        var mutableTag = tag
        return expandedLabels(property: kAudioFormatProperty_ChannelLayoutForTag, specifier: &mutableTag)
    }

    /// タグまたはビットマップを AudioFormatGetProperty で AudioChannelLayout へ展開し、
    /// ラベル列を返す。
    private static func expandedLabels<Specifier>(
        property: AudioFormatPropertyID,
        specifier: inout Specifier
    ) -> [AudioChannelLabel]? {
        let specifierSize = UInt32(MemoryLayout<Specifier>.size)
        var size: UInt32 = 0
        guard AudioFormatGetPropertyInfo(property, specifierSize, &specifier, &size) == noErr,
              Int(size) >= MemoryLayout<AudioChannelLayout>.size else {
            return nil
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioChannelLayout>.alignment
        )
        defer { raw.deallocate() }
        guard AudioFormatGetProperty(property, specifierSize, &specifier, &size, raw) == noErr else {
            return nil
        }
        return labels(from: raw.bindMemory(to: AudioChannelLayout.self, capacity: 1))
    }

    /// AudioChannelLayout の可変長 mChannelDescriptions からラベルを読む。
    /// (structコピーは先頭1要素しか運ばないため、必ずポインタ経由で読む。)
    private static func labels(from pointer: UnsafePointer<AudioChannelLayout>) -> [AudioChannelLabel]? {
        let count = Int(pointer.pointee.mNumberChannelDescriptions)
        guard count > 0,
              let offset = MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions) else {
            return nil
        }
        let descriptions = (UnsafeRawPointer(pointer) + offset)
            .assumingMemoryBound(to: AudioChannelDescription.self)
        return (0..<count).map { descriptions[$0].mChannelLabel }
    }

    static func analyze(
        url: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> TobariMeasurement {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(
                forReading: url,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw TobariAnalysisError.unreadableFile(error.localizedDescription)
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        let channelCount = Int(audioFile.processingFormat.channelCount)
        guard sampleRate > 0, channelCount > 0 else {
            throw TobariAnalysisError.unsupportedFormat("サンプルレートまたはチャンネル数が0です")
        }

        let engine = KitsunebiAnalyzerEngine(
            sampleRate: sampleRate,
            channelCount: channelCount,
            maximumChunkFrames: Int(readBufferFrames),
            channelWeights: channelWeights(for: audioFile.processingFormat),
            correlationChannels: correlationChannels(for: audioFile.processingFormat)
        )

        let totalFrames = max(0, Int(audioFile.length))
        guard totalFrames > 0 else {
            progress?(1.0)
            return engine.finalize()
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: readBufferFrames
        ) else {
            throw TobariAnalysisError.unsupportedFormat("読み込みバッファを確保できません")
        }

        var framesRead = 0
        while framesRead < totalFrames {
            let framesToRead = AVAudioFrameCount(min(Int(readBufferFrames), totalFrames - framesRead))
            do {
                try audioFile.read(into: buffer, frameCount: framesToRead)
            } catch {
                throw TobariAnalysisError.unreadableFile(error.localizedDescription)
            }
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let channelData = buffer.floatChannelData else {
                throw TobariAnalysisError.unsupportedFormat("floatChannelDataを取得できません")
            }
            let pointers = (0..<channelCount).map { UnsafePointer(channelData[$0]) }
            engine.process(channelPointers: pointers, frameCount: n)
            framesRead += n
            progress?(min(1.0, Double(framesRead) / Double(totalFrames)))
        }

        progress?(1.0)
        return engine.finalize()
    }
}
