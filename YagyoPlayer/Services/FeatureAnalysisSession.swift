import Combine
import Foundation

enum FeatureAnalysisSessionError: LocalizedError, Equatable, Sendable {
    case cacheUnavailable

    var errorDescription: String? {
        switch self {
        case .cacheUnavailable:
            return "解析用キャッシュを準備できませんでした。"
        }
    }
}

/// 「一本の耳」を開いている間だけ生きる、control-sideのoffline解析状態。
/// Music Understanding、cache、file I/Oを再生backendやrender callbackへ持ち込まない。
@MainActor
final class FeatureAnalysisSession: ObservableObject {
    enum State: Equatable {
        case idle
        case analyzing
        case ready(FeatureSnapshot)
        case unavailable(String)
    }

    typealias Analyzer = (URL, String) async throws -> FeatureSnapshot

    @Published private(set) var state: State = .idle

    private let analyzer: Analyzer
    private var requestGeneration: UInt64 = 0

    init(analyzer: @escaping Analyzer) {
        self.analyzer = analyzer
    }

    static func live() -> FeatureAnalysisSession {
        guard let cache = try? FeatureSnapshotCache.applicationDefault() else {
            return FeatureAnalysisSession { _, _ in
                throw FeatureAnalysisSessionError.cacheUnavailable
            }
        }
        let service = OfflineFeatureAnalysisService.live(cache: cache)
        return FeatureAnalysisSession { url, sourceFingerprint in
            try await service.snapshot(
                for: url,
                sourceFingerprint: sourceFingerprint
            )
        }
    }

    /// SwiftUI `.task(id:)` からawaitし、sheet close／曲変更のcancellationをpipelineへ伝える。
    func analyze(
        url: URL,
        sourceFingerprint: String
    ) async {
        requestGeneration &+= 1
        let generation = requestGeneration
        state = .analyzing

        do {
            let snapshot = try await analyzer(url, sourceFingerprint)
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            state = .ready(snapshot)
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            state = .idle
        } catch {
            guard generation == requestGeneration else { return }
            state = .unavailable(
                (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            )
        }
    }

    /// 曲未読込やcontent hash準備中は解析を開始せず、理由だけを表示する。
    func markUnavailable(_ message: String) {
        requestGeneration &+= 1
        state = .unavailable(message)
    }
}
