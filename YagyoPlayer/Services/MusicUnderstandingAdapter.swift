import AVFoundation
import CoreMedia
import Foundation

#if canImport(MusicUnderstanding)
import MusicUnderstanding
#endif

/// Music Understanding の可用性を、Apple の型を UI / 再生層へ漏らさず表す。
enum MusicUnderstandingAvailability: String, Codable, Equatable, Sendable {
    /// 現在の SDK と実行 OS で API を参照できる。端末能力は実行時解析で確認する。
    case available
    /// SDK には framework があるが、実行 OS が iOS 27 より古い。
    case requiresIOS27
    /// 現在の SDK に framework がない。
    case frameworkUnavailable
}

enum MusicUnderstandingAdapterError: LocalizedError, Equatable, Sendable {
    case unavailable(MusicUnderstandingAvailability)
    case analysisFailed
    case invalidResult(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(.requiresIOS27):
            return "Music UnderstandingにはiOS 27以降が必要です。"
        case .unavailable(.frameworkUnavailable):
            return "このビルドではMusic Understandingを利用できません。"
        case .unavailable(.available):
            return "Music Understandingを開始できませんでした。"
        case .analysisFailed:
            return "Music Understandingの解析に失敗しました。"
        case .invalidResult(let field):
            return "Music Understandingが無効な解析値を返しました: \(field)"
        }
    }
}

/// Apple の結果型から切り離した、版付き・Codable な解析結果。
/// Phase 0 では API 境界を実証するため六つの解析次元を保持し、
/// 後続 phase で固定長の `FeatureSnapshot` へ集約する。
struct MusicUnderstandingAnalysis: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let analyzerIdentifier = "com.apple.MusicUnderstanding.iOS27.beta"

    var schemaVersion: Int
    var analyzerIdentifier: String
    var analyzedAt: Date
    var loudness: Loudness?
    var rhythm: Rhythm?
    var pace: [RangedScalar]
    var structure: Structure?
    var keys: [KeyRange]
    var instruments: [InstrumentActivity]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        analyzerIdentifier: String = Self.analyzerIdentifier,
        analyzedAt: Date = Date(),
        loudness: Loudness? = nil,
        rhythm: Rhythm? = nil,
        pace: [RangedScalar] = [],
        structure: Structure? = nil,
        keys: [KeyRange] = [],
        instruments: [InstrumentActivity] = []
    ) {
        self.schemaVersion = schemaVersion
        self.analyzerIdentifier = analyzerIdentifier
        self.analyzedAt = analyzedAt
        self.loudness = loudness
        self.rhythm = rhythm
        self.pace = pace
        self.structure = structure
        self.keys = keys
        self.instruments = instruments
    }

    struct TimedScalar: Codable, Equatable, Sendable {
        var timeSeconds: Double
        var value: Double
    }

    struct TimedLoudness: Codable, Equatable, Sendable {
        var timeSeconds: Double
        var reading: LoudnessReading
    }

    struct TimeRange: Codable, Equatable, Sendable {
        var startSeconds: Double
        var durationSeconds: Double
    }

    struct RangedScalar: Codable, Equatable, Sendable {
        var range: TimeRange
        var value: Double
    }

    struct Loudness: Codable, Equatable, Sendable {
        /// Apple が返す BS.1770 integrated loudness。単位は LUFS。
        var integrated: TimedLoudness
        var momentary: [TimedLoudness]
        var shortTerm: [TimedLoudness]
        /// Apple API は `peak` とだけ定義しており、True Peak の根拠には使わない。
        var applePeak: TimedLoudness

        var maxShortTermLUFS: Double? {
            shortTerm.compactMap { $0.reading.finiteValue }.max()
        }
    }

    struct Rhythm: Codable, Equatable, Sendable {
        var beatSeconds: [Double]
        var barSeconds: [Double]
        var beatsPerMinute: Double?
    }

    struct Structure: Codable, Equatable, Sendable {
        var sections: [TimeRange]
        var segments: [TimeRange]
        var phrases: [TimeRange]
    }

    struct KeyRange: Codable, Equatable, Sendable {
        var range: TimeRange
        var tonic: String
        var mode: String
    }

    struct InstrumentActivity: Codable, Equatable, Sendable {
        var instrument: String
        var activeRanges: [TimeRange]
        var activity: [TimedScalar]
    }
}

/// iOS 27 Music Understanding をローカルファイル解析へ閉じ込める境界。
/// この型は render callback から呼ばず、再生開始を待たせないバックグラウンド処理専用。
enum MusicUnderstandingAdapter {
    static var availability: MusicUnderstandingAvailability {
        #if canImport(MusicUnderstanding)
        if #available(iOS 27.0, *) {
            return .available
        }
        return .requiresIOS27
        #else
        return .frameworkUnavailable
        #endif
    }

    static func analyze(url: URL) async throws -> MusicUnderstandingAnalysis {
        switch availability {
        case .available:
            #if canImport(MusicUnderstanding)
            if #available(iOS 27.0, *) {
                return try await analyzeAvailable(url: url)
            }
            #endif
            throw MusicUnderstandingAdapterError.unavailable(.available)
        case .requiresIOS27:
            throw MusicUnderstandingAdapterError.unavailable(.requiresIOS27)
        case .frameworkUnavailable:
            throw MusicUnderstandingAdapterError.unavailable(.frameworkUnavailable)
        }
    }

    #if canImport(MusicUnderstanding)
    @available(iOS 27.0, *)
    private static func analyzeAvailable(url: URL) async throws -> MusicUnderstandingAnalysis {
        do {
            let session = try await MusicUnderstandingSession(asset: AVURLAsset(url: url))

            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let result = try await session.analyze()
                try Task.checkCancellation()
                let analysis = try normalize(result)
                try Task.checkCancellation()
                return analysis
            } onCancel: {
                Task {
                    await session.cancel()
                }
            }
        } catch {
            throw mappedExecutionError(error, taskIsCancelled: Task.isCancelled)
        }
    }

    @available(iOS 27.0, *)
    private static func normalize(
        _ result: MusicUnderstandingSession.SessionResult
    ) throws -> MusicUnderstandingAnalysis {
        try Task.checkCancellation()
        let loudness = try result.loudness.map { value in
            MusicUnderstandingAnalysis.Loudness(
                integrated: try timedLoudness(value.integrated, field: "loudness.integrated"),
                momentary: try value.momentary.enumerated().map { index, sample in
                    try Task.checkCancellation()
                    return try timedLoudness(sample, field: "loudness.momentary[\(index)]")
                },
                shortTerm: try value.shortTerm.enumerated().map { index, sample in
                    try Task.checkCancellation()
                    return try timedLoudness(sample, field: "loudness.shortTerm[\(index)]")
                },
                applePeak: try timedLoudness(value.peak, field: "loudness.peak")
            )
        }

        try Task.checkCancellation()
        let rhythm = try result.rhythm.map { value in
            MusicUnderstandingAnalysis.Rhythm(
                beatSeconds: try value.beats.enumerated().map { index, time in
                    try Task.checkCancellation()
                    return try seconds(time, field: "rhythm.beats[\(index)]")
                },
                barSeconds: try value.bars.enumerated().map { index, time in
                    try Task.checkCancellation()
                    return try seconds(time, field: "rhythm.bars[\(index)]")
                },
                beatsPerMinute: try value.beatsPerMinute.map { bpm in
                    try finite(Double(bpm), field: "rhythm.beatsPerMinute", minimum: 0)
                }
            )
        }

        try Task.checkCancellation()
        let pace = try (result.pace?.ranges ?? []).enumerated().map { index, value in
            try Task.checkCancellation()
            return MusicUnderstandingAnalysis.RangedScalar(
                range: try timeRange(value.range, field: "pace.ranges[\(index)].range"),
                value: try finite(value.value, field: "pace.ranges[\(index)].value")
            )
        }

        try Task.checkCancellation()
        let structure = try result.structure.map { value in
            MusicUnderstandingAnalysis.Structure(
                sections: try normalizedRanges(value.sections, field: "structure.sections"),
                segments: try normalizedRanges(value.segments, field: "structure.segments"),
                phrases: try normalizedRanges(value.phrases, field: "structure.phrases")
            )
        }

        try Task.checkCancellation()
        let keys = try (result.key?.ranges ?? []).enumerated().map { index, value in
            try Task.checkCancellation()
            return MusicUnderstandingAnalysis.KeyRange(
                range: try timeRange(value.range, field: "key.ranges[\(index)].range"),
                tonic: value.value.tonic.rawValue,
                mode: value.value.mode.rawValue
            )
        }

        try Task.checkCancellation()
        let instruments = try normalizedInstruments(result.instrumentActivity)
        try Task.checkCancellation()

        return MusicUnderstandingAnalysis(
            loudness: loudness,
            rhythm: rhythm,
            pace: pace,
            structure: structure,
            keys: keys,
            instruments: instruments
        )
    }

    @available(iOS 27.0, *)
    private static func normalizedInstruments(
        _ result: InstrumentActivityResult?
    ) throws -> [MusicUnderstandingAnalysis.InstrumentActivity] {
        guard let result else { return [] }

        let instruments = Set(result.ranges.keys)
            .union(result.activity.keys)
            .sorted { $0.rawValue < $1.rawValue }

        return try instruments.map { instrument in
            try Task.checkCancellation()
            let ranges = try normalizedRanges(
                result.ranges[instrument] ?? [],
                field: "instrumentActivity.\(instrument.rawValue).ranges"
            )
            let activity = try (result.activity[instrument] ?? []).enumerated().map { index, value in
                try Task.checkCancellation()
                return try timedScalar(
                    value,
                    field: "instrumentActivity.\(instrument.rawValue).activity[\(index)]"
                )
            }
            return MusicUnderstandingAnalysis.InstrumentActivity(
                instrument: instrument.rawValue,
                activeRanges: ranges,
                activity: activity
            )
        }
    }

    @available(iOS 27.0, *)
    private static func normalizedRanges(
        _ ranges: [CMTimeRange],
        field: String
    ) throws -> [MusicUnderstandingAnalysis.TimeRange] {
        try ranges.enumerated().map { index, range in
            try Task.checkCancellation()
            return try timeRange(range, field: "\(field)[\(index)]")
        }
    }

    @available(iOS 27.0, *)
    private static func timedLoudness(
        _ value: MusicUnderstandingSession.TimedValue<Float>,
        field: String
    ) throws -> MusicUnderstandingAnalysis.TimedLoudness {
        MusicUnderstandingAnalysis.TimedLoudness(
            timeSeconds: try seconds(value.time, field: "\(field).time"),
            reading: try loudnessReading(value.value, field: "\(field).value")
        )
    }

    @available(iOS 27.0, *)
    private static func timedScalar(
        _ value: MusicUnderstandingSession.TimedValue<Float>,
        field: String
    ) throws -> MusicUnderstandingAnalysis.TimedScalar {
        MusicUnderstandingAnalysis.TimedScalar(
            timeSeconds: try seconds(value.time, field: "\(field).time"),
            value: try finite(Double(value.value), field: "\(field).value")
        )
    }

    #endif

    static func mappedExecutionError(
        _ error: Error,
        taskIsCancelled: Bool
    ) -> Error {
        if taskIsCancelled || error is CancellationError {
            return CancellationError()
        }
        if let adapterError = error as? MusicUnderstandingAdapterError {
            return adapterError
        }
        return MusicUnderstandingAdapterError.analysisFailed
    }

    static func loudnessReading(
        _ value: Float,
        field: String
    ) throws -> LoudnessReading {
        if value.isFinite {
            return .finite(Double(value))
        }
        if value == -.infinity {
            return .negativeInfinity
        }
        throw MusicUnderstandingAdapterError.invalidResult(field)
    }

    static func timeRange(
        _ range: CMTimeRange,
        field: String
    ) throws -> MusicUnderstandingAnalysis.TimeRange {
        MusicUnderstandingAnalysis.TimeRange(
            startSeconds: try seconds(range.start, field: "\(field).start"),
            durationSeconds: try seconds(range.duration, field: "\(field).duration")
        )
    }

    static func seconds(_ time: CMTime, field: String) throws -> Double {
        try finite(CMTimeGetSeconds(time), field: field, minimum: 0)
    }

    static func finite(
        _ value: Double,
        field: String,
        minimum: Double? = nil
    ) throws -> Double {
        guard value.isFinite, minimum.map({ value >= $0 }) ?? true else {
            throw MusicUnderstandingAdapterError.invalidResult(field)
        }
        return value
    }
}
