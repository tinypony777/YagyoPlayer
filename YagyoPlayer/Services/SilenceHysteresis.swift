import Foundation

/// Codable に非有限値を保存せず、デジタル無音と未取得を区別する loudness 値。
enum LoudnessReading: Codable, Equatable, Sendable {
    case finite(Double)
    case negativeInfinity
    case unavailable

    var finiteValue: Double? {
        guard case .finite(let value) = self, value.isFinite else { return nil }
        return value
    }
}

struct SilenceHysteresisSummary: Codable, Equatable, Sendable {
    var observedSampleCount: Int
    var silentSampleCount: Int

    var silentRatio: Double? {
        guard observedSampleCount > 0 else { return nil }
        return Double(silentSampleCount) / Double(observedSampleCount)
    }

    var isEntirelySilent: Bool {
        observedSampleCount > 0 && silentSampleCount == observedSampleCount
    }
}

/// Music Understanding の momentary loudness を入力にする純粋な無音 reducer。
/// `<= -70 LUFS` で無音へ入り、`> -65 LUFS` で抜ける5 LUのhysteresisを持つ。
/// unavailable / non-finite は状態と集計を変えない。
struct SilenceHysteresis: Sendable {
    static let entryThresholdLUFS = -70.0
    static let exitThresholdLUFS = -65.0

    private(set) var isSilent = false
    private(set) var observedSampleCount = 0
    private(set) var silentSampleCount = 0

    @discardableResult
    mutating func observe(_ reading: LoudnessReading) -> Bool {
        let comparableValue: Double
        switch reading {
        case .negativeInfinity:
            comparableValue = -.infinity
        case .finite(let value) where value.isFinite:
            comparableValue = value
        case .finite, .unavailable:
            return isSilent
        }

        if isSilent {
            if comparableValue > Self.exitThresholdLUFS {
                isSilent = false
            }
        } else if comparableValue <= Self.entryThresholdLUFS {
            isSilent = true
        }

        observedSampleCount += 1
        if isSilent {
            silentSampleCount += 1
        }
        return isSilent
    }

    var summary: SilenceHysteresisSummary {
        SilenceHysteresisSummary(
            observedSampleCount: observedSampleCount,
            silentSampleCount: silentSampleCount
        )
    }
}

extension MusicUnderstandingAnalysis.Loudness {
    var silenceSummary: SilenceHysteresisSummary {
        var detector = SilenceHysteresis()
        for sample in momentary {
            detector.observe(sample.reading)
        }
        return detector.summary
    }
}
