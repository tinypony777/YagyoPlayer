import Foundation

/// Codable に非有限値を保存せず、デジタル無音と未取得を区別する loudness 値。
enum LoudnessReading: Codable, Equatable, Sendable {
    case finite(Double)
    case negativeInfinity
    case unavailable

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case finite
        case negativeInfinity
        case unavailable
    }

    private enum FiniteCodingKeys: String, CodingKey {
        case value = "_0"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let presentCases = CodingKeys.allCases.filter(container.contains)
        guard presentCases.count == 1, let presentCase = presentCases.first else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "A loudness reading must contain exactly one case."
                )
            )
        }

        switch presentCase {
        case .finite:
            let finiteContainer = try container.nestedContainer(
                keyedBy: FiniteCodingKeys.self,
                forKey: .finite
            )
            let value = try finiteContainer.decode(Double.self, forKey: .value)
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: finiteContainer,
                    debugDescription: "A finite loudness reading must contain a finite value."
                )
            }
            self = .finite(value)
        case .negativeInfinity:
            self = .negativeInfinity
        case .unavailable:
            self = .unavailable
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .finite(let value) where value.isFinite:
            var finiteContainer = container.nestedContainer(
                keyedBy: FiniteCodingKeys.self,
                forKey: .finite
            )
            try finiteContainer.encode(value, forKey: .value)
        case .negativeInfinity:
            _ = container.nestedContainer(
                keyedBy: FiniteCodingKeys.self,
                forKey: .negativeInfinity
            )
        case .finite, .unavailable:
            // A defensive direct construction such as `.finite(.nan)` is persisted
            // as unavailable rather than making the entire Codable payload fail.
            _ = container.nestedContainer(
                keyedBy: FiniteCodingKeys.self,
                forKey: .unavailable
            )
        }
    }

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
