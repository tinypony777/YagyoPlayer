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
