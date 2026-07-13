import Foundation

/// 狐火の帳で比較する二つの再生側。A は帳を開いた対象、B は参照トラック。
enum TobariABSide: String, CaseIterable, Sendable {
    case subject
    case reference
}

/// A/B用の減衰を、比較対象でない再生トラックへ漏らさないためのID境界。
struct TobariABPair: Equatable, Sendable {
    let subjectTrackID: AudioTrack.ID
    let referenceTrackID: AudioTrack.ID

    func trackID(for side: TobariABSide) -> AudioTrack.ID {
        switch side {
        case .subject:
            subjectTrackID
        case .reference:
            referenceTrackID
        }
    }

    func contains(_ trackID: AudioTrack.ID?) -> Bool {
        trackID == subjectTrackID || trackID == referenceTrackID
    }

    func canApply(to currentTrackID: AudioTrack.ID?, activeSide: TobariABSide) -> Bool {
        currentTrackID == trackID(for: activeSide)
    }
}

/// Integrated Loudness の差から作る、減衰だけのA/B比較ゲイン。
///
/// 両方を小さい方のLUFSへ揃えるため、どちらのゲインも必ず0 dB以下になる。
/// 非有限値や未計測値から推測せず、その場合は比較自体を利用不能にする。
struct TobariLoudnessMatch: Equatable, Sendable {
    let targetLUFS: Double
    let subjectGainDB: Double
    let referenceGainDB: Double

    init?(subjectIntegratedLUFS: Double?, referenceIntegratedLUFS: Double?) {
        guard let subjectIntegratedLUFS,
              let referenceIntegratedLUFS,
              subjectIntegratedLUFS.isFinite,
              referenceIntegratedLUFS.isFinite else {
            return nil
        }

        let targetLUFS = min(subjectIntegratedLUFS, referenceIntegratedLUFS)
        let subjectGainDB = targetLUFS - subjectIntegratedLUFS
        let referenceGainDB = targetLUFS - referenceIntegratedLUFS
        guard subjectGainDB.isFinite, referenceGainDB.isFinite else { return nil }

        self.targetLUFS = targetLUFS
        self.subjectGainDB = min(0, subjectGainDB)
        self.referenceGainDB = min(0, referenceGainDB)
    }

    func gainDB(for side: TobariABSide) -> Double {
        switch side {
        case .subject:
            subjectGainDB
        case .reference:
            referenceGainDB
        }
    }

    func multiplier(for side: TobariABSide) -> Float {
        let linear = pow(10, gainDB(for: side) / 20)
        guard linear.isFinite else { return 1 }
        return Float(min(max(linear, 0), 1))
    }
}
