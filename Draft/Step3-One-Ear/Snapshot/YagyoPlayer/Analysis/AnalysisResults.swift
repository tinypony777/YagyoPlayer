import Foundation

struct RealtimeAnalysisSnapshot: Equatable, Sendable {
    let level: Double
    let momentaryLUFS: Double?
    let shortTermLUFS: Double?
    let isSilent: Bool
    let onsetStrength: Double
    let onsetSequence: UInt64
    let droppedAnalysisBlockCount: UInt64
    let hasDiscontinuity: Bool

    static let unavailable = RealtimeAnalysisSnapshot(
        level: 0,
        momentaryLUFS: nil,
        shortTermLUFS: nil,
        isSilent: false,
        onsetStrength: 0,
        onsetSequence: 0,
        droppedAnalysisBlockCount: 0,
        hasDiscontinuity: false
    )
}

enum TrackAnalysisStatus: String, Codable, Equatable, Hashable, Sendable {
    case complete, silent, tooShort, unsupported
}

struct OfflineTrackAnalysis: Equatable, Sendable {
    let status: TrackAnalysisStatus
    let integratedLUFS: Double?
    let maximumMomentaryLUFS: Double?
    let maximumShortTermLUFS: Double?
    let analyzedDuration: TimeInterval
    let silentDuration: TimeInterval
    let silentRatio: Double
    let onsetCount: Int
    let meanOnsetRate: Double
}
