import Foundation

/// 狐火の帳(Step 5 Phase A)の検聴結果。
/// `contentHash` + `analyzerVersion` をキーに library.json へキャッシュされる。
/// 値が nil の指標は「計測不能(無音等)」を表す。JSONへ無限大を書かないための契約。
struct TobariMetrics: Codable, Hashable, Sendable {
    /// 解析アルゴリズムの版。指標の定義や係数を変えたら上げ、旧キャッシュを無効化する。
    var analyzerVersion: Int
    /// 解析した音源の SHA-256。トラックの contentHash と一致する間だけキャッシュ有効。
    var contentHash: String?
    var analyzedAt: Date
    var sampleRate: Double
    var durationSeconds: Double
    var channelCount: Int

    /// Integrated Loudness (LUFS, ITU-R BS.1770-4)。
    var integratedLUFS: Double?
    /// Short-term (3秒窓) の最大値 (LUFS)。
    var maxShortTermLUFS: Double?
    /// サンプルピーク (dBFS)。
    var samplePeakDBFS: Double?
    /// 4xオーバーサンプリングFIR補間による True Peak (dBTP)。
    var truePeakDBTP: Double?
    /// クリップ疑い: |x| ≥ 0.999 が3サンプル以上連続したランの総数(全チャンネル)。
    var clipRunCount: Int
    /// クリップ疑いランの開始位置(秒)。先頭から最大8件。
    var clipRunSeconds: [Double]
    /// L/R の位相相関係数 (-1...+1)。nil はモノラル音源。
    var stereoCorrelation: Double?
}

/// 帳に表示する根拠付きの提案。「補正」ではなく提案(§3 音への敬意)。
struct TobariSuggestion: Identifiable, Hashable, Sendable {
    var id: String
    /// 提案の本文。
    var text: String
    /// 判断の根拠になった実測値。
    var basis: String
}

extension TobariMetrics {
    static let currentAnalyzerVersion = 1

    /// キャッシュが現在のトラックとアナライザ版に対して有効か。
    func isValidCache(for contentHash: String?) -> Bool {
        guard analyzerVersion == Self.currentAnalyzerVersion else { return false }
        guard let contentHash, let own = self.contentHash else { return false }
        return contentHash == own
    }

    /// 根拠付きの提案を組み立てる。自動では何も直さない。
    var suggestions: [TobariSuggestion] {
        var results: [TobariSuggestion] = []

        if let truePeakDBTP, truePeakDBTP > -1.0 {
            results.append(
                TobariSuggestion(
                    id: "truePeak",
                    text: "書き出し時のリミッタ余裕(-1.0 dBTP以下)の確認を提案します。",
                    basis: String(format: "True Peak %.2f dBTP", truePeakDBTP)
                )
            )
        }

        if clipRunCount > 0 {
            let positions = clipRunSeconds
                .prefix(3)
                .map { Self.timeText($0) }
                .joined(separator: ", ")
            results.append(
                TobariSuggestion(
                    id: "clip",
                    text: "フルスケール付近の連続サンプルがあります。書き出し前の波形確認を提案します。",
                    basis: positions.isEmpty
                        ? "クリップ疑い \(clipRunCount) 箇所"
                        : "クリップ疑い \(clipRunCount) 箇所(先頭: \(positions))"
                )
            )
        }

        if let stereoCorrelation, stereoCorrelation < 0.2 {
            results.append(
                TobariSuggestion(
                    id: "monoCompat",
                    text: "モノラル再生での打ち消しの確認を提案します。",
                    basis: String(format: "L/R位相相関 %.2f", stereoCorrelation)
                )
            )
        }

        return results
    }

    // MARK: - 表示用フォーマッタ(狐火の目盛)

    var integratedText: String { Self.lufsText(integratedLUFS) }
    var maxShortTermText: String { Self.lufsText(maxShortTermLUFS) }
    var samplePeakText: String { Self.dbText(samplePeakDBFS, unit: "dBFS") }
    var truePeakText: String { Self.dbText(truePeakDBTP, unit: "dBTP") }

    var clipText: String {
        clipRunCount == 0 ? "なし" : "\(clipRunCount) 箇所"
    }

    var monoCompatText: String {
        guard let stereoCorrelation else { return "モノラル音源" }
        return String(format: "%.2f", stereoCorrelation)
    }

    private static func lufsText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "計測不能" }
        return String(format: "%.1f LUFS", value)
    }

    private static func dbText(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite else { return "計測不能" }
        return String(format: "%.2f %@", value, unit)
    }

    static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
