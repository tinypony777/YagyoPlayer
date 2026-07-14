import Foundation

enum FeatureSnapshotValidationError: LocalizedError, Equatable, Sendable {
    case invalidSourceFingerprint
    case versionMismatch(String)
    case nonFinite(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidSourceFingerprint:
            return "音源フィンガープリントが有効なSHA-256ではありません。"
        case .versionMismatch(let field):
            return "解析キャッシュの版が一致しません: \(field)"
        case .nonFinite(let field):
            return "解析キャッシュに非有限値があります: \(field)"
        case .invalidValue(let field):
            return "解析キャッシュに無効な値があります: \(field)"
        }
    }
}

/// Music Understanding と狐火メーターの結果を、Core AIへ渡せる固定上限の値へ集約する。
/// 生PCM、Apple frameworkの型、無制限のtimelineは保持しない。
struct FeatureSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let currentAnalyzerVersion = "yagyo-bounded-features-v1-mu\(MusicUnderstandingAnalysis.currentSchemaVersion)-kitsunebi\(TobariMetrics.currentAnalyzerVersion)"
    static let currentCompatibilityKey = "music-understanding-ios27-beta-v1"
    static let maximumInstrumentCount = 16

    enum Availability: String, Codable, Equatable, Sendable {
        /// 解析自体が完了した状態。個々のApple結果がnilであることは許容する。
        case complete
    }

    struct BoundedFiniteFeatures: Codable, Equatable, Sendable {
        /// Music Understandingの可変長timelineを固定上限の要約へ変換した値。
        var musicUnderstanding: MusicUnderstandingFeatures
        /// Step 5と同じ型・同じKitsunebi実装を正本にする安全計測値。
        var kitsunebi: TobariMetrics
    }

    struct MusicUnderstandingFeatures: Codable, Equatable, Sendable {
        struct DominantKey: Codable, Equatable, Sendable {
            var tonic: String
            var mode: String
            var observedDurationSeconds: Double
        }

        struct Instrument: Codable, Equatable, Sendable {
            var identifier: String
            var activeRangeCount: Int
            var activitySampleCount: Int
            var meanActivity: Double?
        }

        var beatsPerMinute: Double?
        var beatCount: Int
        var barCount: Int
        var meanPace: Double?
        var sectionCount: Int
        var segmentCount: Int
        var phraseCount: Int
        var silenceSummary: SilenceHysteresisSummary
        var dominantKey: DominantKey?
        /// mean activity降順、identifier昇順の決定論的な上位16件。
        var instruments: [Instrument]
    }

    var schemaVersion: Int
    var sourceFingerprint: String
    var analyzerVersion: String
    var compatibilityKey: String
    var availability: Availability
    var boundedFiniteFeatures: BoundedFiniteFeatures
    var createdAt: Date

    /// ディスクへ出す直前と復元直後に通す共通検証。
    func validateForCaching() throws {
        try Self.validateSourceFingerprint(sourceFingerprint)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw FeatureSnapshotValidationError.versionMismatch("schemaVersion")
        }
        guard analyzerVersion == Self.currentAnalyzerVersion else {
            throw FeatureSnapshotValidationError.versionMismatch("analyzerVersion")
        }
        guard compatibilityKey == Self.currentCompatibilityKey else {
            throw FeatureSnapshotValidationError.versionMismatch("compatibilityKey")
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw FeatureSnapshotValidationError.nonFinite("createdAt")
        }

        try validateMusicUnderstandingFeatures()
        try validateKitsunebiFeatures()
    }

    func isValidCache(for sourceFingerprint: String) -> Bool {
        guard self.sourceFingerprint == sourceFingerprint else { return false }
        do {
            try validateForCaching()
            return true
        } catch {
            return false
        }
    }

    static func validateSourceFingerprint(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard bytes.count == 64,
              bytes.allSatisfy({ byte in
                  (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                      || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
              }) else {
            throw FeatureSnapshotValidationError.invalidSourceFingerprint
        }
    }

    private func validateMusicUnderstandingFeatures() throws {
        let music = boundedFiniteFeatures.musicUnderstanding
        try Self.validateOptionalFinite(
            music.beatsPerMinute,
            field: "boundedFiniteFeatures.musicUnderstanding.beatsPerMinute"
        )
        if let beatsPerMinute = music.beatsPerMinute, beatsPerMinute < 0 {
            throw FeatureSnapshotValidationError.invalidValue(
                "boundedFiniteFeatures.musicUnderstanding.beatsPerMinute"
            )
        }
        try Self.validateOptionalFinite(
            music.meanPace,
            field: "boundedFiniteFeatures.musicUnderstanding.meanPace"
        )

        let counts: [(String, Int)] = [
            ("beatCount", music.beatCount),
            ("barCount", music.barCount),
            ("sectionCount", music.sectionCount),
            ("segmentCount", music.segmentCount),
            ("phraseCount", music.phraseCount),
            ("silenceSummary.observedSampleCount", music.silenceSummary.observedSampleCount),
            ("silenceSummary.silentSampleCount", music.silenceSummary.silentSampleCount)
        ]
        for (field, value) in counts where value < 0 {
            throw FeatureSnapshotValidationError.invalidValue(
                "boundedFiniteFeatures.musicUnderstanding.\(field)"
            )
        }
        guard music.silenceSummary.silentSampleCount <= music.silenceSummary.observedSampleCount else {
            throw FeatureSnapshotValidationError.invalidValue(
                "boundedFiniteFeatures.musicUnderstanding.silenceSummary"
            )
        }

        if let key = music.dominantKey {
            try Self.validateIdentifier(
                key.tonic,
                field: "boundedFiniteFeatures.musicUnderstanding.dominantKey.tonic"
            )
            try Self.validateIdentifier(
                key.mode,
                field: "boundedFiniteFeatures.musicUnderstanding.dominantKey.mode"
            )
            try Self.validateFinite(
                key.observedDurationSeconds,
                field: "boundedFiniteFeatures.musicUnderstanding.dominantKey.observedDurationSeconds"
            )
            guard key.observedDurationSeconds >= 0 else {
                throw FeatureSnapshotValidationError.invalidValue(
                    "boundedFiniteFeatures.musicUnderstanding.dominantKey.observedDurationSeconds"
                )
            }
        }

        guard music.instruments.count <= Self.maximumInstrumentCount else {
            throw FeatureSnapshotValidationError.invalidValue(
                "boundedFiniteFeatures.musicUnderstanding.instruments"
            )
        }
        var identifiers = Set<String>()
        for (index, instrument) in music.instruments.enumerated() {
            let prefix = "boundedFiniteFeatures.musicUnderstanding.instruments[\(index)]"
            try Self.validateIdentifier(instrument.identifier, field: "\(prefix).identifier")
            guard identifiers.insert(instrument.identifier).inserted,
                  instrument.activeRangeCount >= 0,
                  instrument.activitySampleCount >= 0 else {
                throw FeatureSnapshotValidationError.invalidValue(prefix)
            }
            try Self.validateOptionalFinite(
                instrument.meanActivity,
                field: "\(prefix).meanActivity"
            )
        }
    }

    private func validateKitsunebiFeatures() throws {
        let metrics = boundedFiniteFeatures.kitsunebi
        guard metrics.analyzerVersion == TobariMetrics.currentAnalyzerVersion else {
            throw FeatureSnapshotValidationError.versionMismatch(
                "boundedFiniteFeatures.kitsunebi.analyzerVersion"
            )
        }
        guard metrics.contentHash == sourceFingerprint else {
            throw FeatureSnapshotValidationError.invalidValue(
                "boundedFiniteFeatures.kitsunebi.contentHash"
            )
        }
        guard metrics.analyzedAt == createdAt else {
            throw FeatureSnapshotValidationError.invalidValue(
                "boundedFiniteFeatures.kitsunebi.analyzedAt"
            )
        }

        try Self.validateFinite(
            metrics.sampleRate,
            field: "boundedFiniteFeatures.kitsunebi.sampleRate"
        )
        try Self.validateFinite(
            metrics.durationSeconds,
            field: "boundedFiniteFeatures.kitsunebi.durationSeconds"
        )
        guard metrics.sampleRate > 0, metrics.durationSeconds >= 0, metrics.channelCount > 0 else {
            throw FeatureSnapshotValidationError.invalidValue(
                "boundedFiniteFeatures.kitsunebi.format"
            )
        }

        let optionalMetrics: [(String, Double?)] = [
            ("integratedLUFS", metrics.integratedLUFS),
            ("maxShortTermLUFS", metrics.maxShortTermLUFS),
            ("samplePeakDBFS", metrics.samplePeakDBFS),
            ("truePeakDBTP", metrics.truePeakDBTP),
            ("stereoCorrelation", metrics.stereoCorrelation)
        ]
        for (field, value) in optionalMetrics {
            try Self.validateOptionalFinite(
                value,
                field: "boundedFiniteFeatures.kitsunebi.\(field)"
            )
        }
        if let correlation = metrics.stereoCorrelation,
           !(-1.0...1.0).contains(correlation) {
            throw FeatureSnapshotValidationError.invalidValue(
                "boundedFiniteFeatures.kitsunebi.stereoCorrelation"
            )
        }
        guard metrics.clipRunCount >= 0, metrics.clipRunSeconds.count <= 8 else {
            throw FeatureSnapshotValidationError.invalidValue(
                "boundedFiniteFeatures.kitsunebi.clipRuns"
            )
        }
        for (index, seconds) in metrics.clipRunSeconds.enumerated() {
            try Self.validateFinite(
                seconds,
                field: "boundedFiniteFeatures.kitsunebi.clipRunSeconds[\(index)]"
            )
            guard seconds >= 0 else {
                throw FeatureSnapshotValidationError.invalidValue(
                    "boundedFiniteFeatures.kitsunebi.clipRunSeconds[\(index)]"
                )
            }
        }
    }

    private static func validateIdentifier(_ value: String, field: String) throws {
        guard !value.isEmpty, value.utf8.count <= 64 else {
            throw FeatureSnapshotValidationError.invalidValue(field)
        }
    }

    private static func validateOptionalFinite(_ value: Double?, field: String) throws {
        guard let value else { return }
        try validateFinite(value, field: field)
    }

    private static func validateFinite(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw FeatureSnapshotValidationError.nonFinite(field)
        }
    }
}
