import Foundation

/// Music Understandingの可変長結果とKitsunebiの安全計測を、固定上限のcache payloadへ束ねる純粋境界。
/// 狐火の帳と同じKitsunebi測定値を再利用し、独自LUFS／True Peak実装は増やさない。
enum BoundedDSPFeatureExtractor {
    static let maximumInstrumentCount = FeatureSnapshot.maximumInstrumentCount

    static func makeSnapshot(
        sourceFingerprint: String,
        musicUnderstanding: MusicUnderstandingAnalysis,
        kitsunebi: TobariMeasurement,
        createdAt: Date = Date()
    ) throws -> FeatureSnapshot {
        try FeatureSnapshot.validateSourceFingerprint(sourceFingerprint)
        try validate(musicUnderstanding)

        let snapshot = FeatureSnapshot(
            schemaVersion: FeatureSnapshot.currentSchemaVersion,
            sourceFingerprint: sourceFingerprint,
            analyzerVersion: FeatureSnapshot.currentAnalyzerVersion,
            compatibilityKey: FeatureSnapshot.currentCompatibilityKey,
            availability: .complete,
            boundedFiniteFeatures: .init(
                musicUnderstanding: summarize(musicUnderstanding),
                kitsunebi: TobariMetrics(
                    measurement: kitsunebi,
                    contentHash: sourceFingerprint,
                    analyzedAt: createdAt
                )
            ),
            createdAt: createdAt
        )
        try snapshot.validateForCaching()
        return snapshot
    }

    private static func summarize(
        _ analysis: MusicUnderstandingAnalysis
    ) -> FeatureSnapshot.MusicUnderstandingFeatures {
        let dominantKey = analysis.keys
            .sorted { lhs, rhs in
                if lhs.range.durationSeconds != rhs.range.durationSeconds {
                    return lhs.range.durationSeconds > rhs.range.durationSeconds
                }
                if lhs.range.startSeconds != rhs.range.startSeconds {
                    return lhs.range.startSeconds < rhs.range.startSeconds
                }
                if lhs.tonic != rhs.tonic {
                    return lhs.tonic < rhs.tonic
                }
                return lhs.mode < rhs.mode
            }
            .first
            .map { value in
                FeatureSnapshot.MusicUnderstandingFeatures.DominantKey(
                    tonic: value.tonic,
                    mode: value.mode,
                    observedDurationSeconds: value.range.durationSeconds
                )
            }

        let instruments = analysis.instruments
            .map { instrument in
                FeatureSnapshot.MusicUnderstandingFeatures.Instrument(
                    identifier: instrument.instrument,
                    activeRangeCount: instrument.activeRanges.count,
                    activitySampleCount: instrument.activity.count,
                    meanActivity: incrementalMean(instrument.activity.map(\.value))
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.meanActivity, rhs.meanActivity) {
                case let (left?, right?) where left != right:
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.identifier < rhs.identifier
                }
            }

        return FeatureSnapshot.MusicUnderstandingFeatures(
            beatsPerMinute: analysis.rhythm?.beatsPerMinute,
            beatCount: analysis.rhythm?.beatSeconds.count ?? 0,
            barCount: analysis.rhythm?.barSeconds.count ?? 0,
            meanPace: incrementalMean(analysis.pace.map(\.value)),
            sectionCount: analysis.structure?.sections.count ?? 0,
            segmentCount: analysis.structure?.segments.count ?? 0,
            phraseCount: analysis.structure?.phrases.count ?? 0,
            silenceSummary: analysis.loudness?.silenceSummary ?? SilenceHysteresis().summary,
            dominantKey: dominantKey,
            instruments: Array(instruments.prefix(maximumInstrumentCount))
        )
    }

    private static func validate(_ analysis: MusicUnderstandingAnalysis) throws {
        guard analysis.schemaVersion == MusicUnderstandingAnalysis.currentSchemaVersion else {
            throw FeatureSnapshotValidationError.versionMismatch(
                "musicUnderstanding.schemaVersion"
            )
        }
        guard analysis.analyzerIdentifier == MusicUnderstandingAnalysis.analyzerIdentifier else {
            throw FeatureSnapshotValidationError.versionMismatch(
                "musicUnderstanding.analyzerIdentifier"
            )
        }
        try finiteDate(analysis.analyzedAt, field: "musicUnderstanding.analyzedAt")

        if let loudness = analysis.loudness {
            try validate(loudness.integrated, field: "musicUnderstanding.loudness.integrated")
            for (index, value) in loudness.momentary.enumerated() {
                try validate(
                    value,
                    field: "musicUnderstanding.loudness.momentary[\(index)]"
                )
            }
            for (index, value) in loudness.shortTerm.enumerated() {
                try validate(
                    value,
                    field: "musicUnderstanding.loudness.shortTerm[\(index)]"
                )
            }
            try validate(loudness.applePeak, field: "musicUnderstanding.loudness.applePeak")
        }

        if let rhythm = analysis.rhythm {
            for (index, seconds) in rhythm.beatSeconds.enumerated() {
                try nonnegativeFinite(
                    seconds,
                    field: "musicUnderstanding.rhythm.beatSeconds[\(index)]"
                )
            }
            for (index, seconds) in rhythm.barSeconds.enumerated() {
                try nonnegativeFinite(
                    seconds,
                    field: "musicUnderstanding.rhythm.barSeconds[\(index)]"
                )
            }
            if let beatsPerMinute = rhythm.beatsPerMinute {
                try nonnegativeFinite(
                    beatsPerMinute,
                    field: "musicUnderstanding.rhythm.beatsPerMinute"
                )
            }
        }

        for (index, value) in analysis.pace.enumerated() {
            try validate(value.range, field: "musicUnderstanding.pace[\(index)].range")
            try finite(value.value, field: "musicUnderstanding.pace[\(index)].value")
        }

        if let structure = analysis.structure {
            try validate(
                structure.sections,
                field: "musicUnderstanding.structure.sections"
            )
            try validate(
                structure.segments,
                field: "musicUnderstanding.structure.segments"
            )
            try validate(
                structure.phrases,
                field: "musicUnderstanding.structure.phrases"
            )
        }

        for (index, key) in analysis.keys.enumerated() {
            try validate(key.range, field: "musicUnderstanding.keys[\(index)].range")
            try identifier(key.tonic, field: "musicUnderstanding.keys[\(index)].tonic")
            try identifier(key.mode, field: "musicUnderstanding.keys[\(index)].mode")
        }

        var instrumentIdentifiers = Set<String>()
        for (index, instrument) in analysis.instruments.enumerated() {
            let prefix = "musicUnderstanding.instruments[\(index)]"
            try identifier(instrument.instrument, field: "\(prefix).identifier")
            guard instrumentIdentifiers.insert(instrument.instrument).inserted else {
                throw FeatureSnapshotValidationError.invalidValue("\(prefix).identifier")
            }
            try validate(instrument.activeRanges, field: "\(prefix).activeRanges")
            for (activityIndex, activity) in instrument.activity.enumerated() {
                try nonnegativeFinite(
                    activity.timeSeconds,
                    field: "\(prefix).activity[\(activityIndex)].timeSeconds"
                )
                try finite(
                    activity.value,
                    field: "\(prefix).activity[\(activityIndex)].value"
                )
            }
        }
    }

    private static func validate(
        _ values: [MusicUnderstandingAnalysis.TimeRange],
        field: String
    ) throws {
        for (index, value) in values.enumerated() {
            try validate(value, field: "\(field)[\(index)]")
        }
    }

    private static func validate(
        _ range: MusicUnderstandingAnalysis.TimeRange,
        field: String
    ) throws {
        try nonnegativeFinite(range.startSeconds, field: "\(field).startSeconds")
        try nonnegativeFinite(range.durationSeconds, field: "\(field).durationSeconds")
    }

    private static func validate(
        _ value: MusicUnderstandingAnalysis.TimedLoudness,
        field: String
    ) throws {
        try nonnegativeFinite(value.timeSeconds, field: "\(field).timeSeconds")
        if case .finite(let reading) = value.reading {
            try finite(reading, field: "\(field).reading")
        }
    }

    private static func incrementalMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        var mean = 0.0
        for (index, value) in values.enumerated() {
            mean += (value - mean) / Double(index + 1)
        }
        return mean
    }

    private static func identifier(_ value: String, field: String) throws {
        guard !value.isEmpty, value.utf8.count <= 64 else {
            throw FeatureSnapshotValidationError.invalidValue(field)
        }
    }

    private static func finiteDate(_ value: Date, field: String) throws {
        try finite(value.timeIntervalSinceReferenceDate, field: field)
    }

    private static func nonnegativeFinite(_ value: Double, field: String) throws {
        try finite(value, field: field)
        guard value >= 0 else {
            throw FeatureSnapshotValidationError.invalidValue(field)
        }
    }

    private static func finite(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw FeatureSnapshotValidationError.nonFinite(field)
        }
    }
}
