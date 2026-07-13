import Foundation

/// FeatureSnapshot専用のローカルJSON cache。
/// actor外へencoder／FileManagerを出さず、render callbackや再生開始経路からは呼ばない。
actor FeatureSnapshotCache {
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    /// Application Supportではなくpurge可能なCaches配下を使う。解析結果は常に再生成可能。
    static func applicationDefault() throws -> FeatureSnapshotCache {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return FeatureSnapshotCache(
            directoryURL: caches.appendingPathComponent("FeatureSnapshots", isDirectory: true)
        )
    }

    func load(sourceFingerprint: String) throws -> FeatureSnapshot? {
        try Task.checkCancellation()
        try FeatureSnapshot.validateSourceFingerprint(sourceFingerprint)
        let url = entryURL(for: sourceFingerprint)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try Task.checkCancellation()

        do {
            let snapshot = try decoder.decode(FeatureSnapshot.self, from: data)
            guard snapshot.isValidCache(for: sourceFingerprint) else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return snapshot
        } catch {
            // 破損・未知schema・未知enumは通常のcache missとして削除し、再解析を許可する。
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    func store(_ snapshot: FeatureSnapshot) throws {
        try Task.checkCancellation()
        try snapshot.validateForCaching()
        let data = try encoder.encode(snapshot)
        try Task.checkCancellation()

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try Task.checkCancellation()
        try data.write(
            to: entryURL(for: snapshot.sourceFingerprint),
            options: [.atomic]
        )
        do {
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(
                at: entryURL(for: snapshot.sourceFingerprint)
            )
            throw error
        }
    }

    func remove(sourceFingerprint: String) throws {
        try FeatureSnapshot.validateSourceFingerprint(sourceFingerprint)
        let url = entryURL(for: sourceFingerprint)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func entryURL(for sourceFingerprint: String) -> URL {
        directoryURL.appendingPathComponent("\(sourceFingerprint).json", isDirectory: false)
    }
}

/// Phase 2の非リアルタイム解析pipeline。cache miss時だけMusic UnderstandingとKitsunebiを実行する。
/// 解析・ファイルI/Oは再生backend、AU、render callbackから完全に分離する。
struct OfflineFeatureAnalysisService: Sendable {
    typealias MusicAnalyzer = @Sendable (URL) async throws -> MusicUnderstandingAnalysis
    typealias KitsunebiAnalyzerClosure = @Sendable (URL) async throws -> TobariMeasurement
    typealias Clock = @Sendable () -> Date

    private let cache: FeatureSnapshotCache
    private let musicAnalyzer: MusicAnalyzer
    private let kitsunebiAnalyzer: KitsunebiAnalyzerClosure
    private let clock: Clock

    init(
        cache: FeatureSnapshotCache,
        musicAnalyzer: @escaping MusicAnalyzer,
        kitsunebiAnalyzer: @escaping KitsunebiAnalyzerClosure,
        clock: @escaping Clock = Date.init
    ) {
        self.cache = cache
        self.musicAnalyzer = musicAnalyzer
        self.kitsunebiAnalyzer = kitsunebiAnalyzer
        self.clock = clock
    }

    static func live(cache: FeatureSnapshotCache) -> OfflineFeatureAnalysisService {
        OfflineFeatureAnalysisService(
            cache: cache,
            musicAnalyzer: { url in
                try await MusicUnderstandingAdapter.analyze(url: url)
            },
            kitsunebiAnalyzer: { url in
                try await analyzeKitsunebiOffMain(url: url)
            }
        )
    }

    func snapshot(
        for url: URL,
        sourceFingerprint: String
    ) async throws -> FeatureSnapshot {
        try Task.checkCancellation()
        if let cached = try await cache.load(sourceFingerprint: sourceFingerprint) {
            return cached
        }

        let musicUnderstanding = try await musicAnalyzer(url)
        try Task.checkCancellation()
        let kitsunebi = try await kitsunebiAnalyzer(url)
        try Task.checkCancellation()

        let snapshot = try BoundedDSPFeatureExtractor.makeSnapshot(
            sourceFingerprint: sourceFingerprint,
            musicUnderstanding: musicUnderstanding,
            kitsunebi: kitsunebi,
            createdAt: clock()
        )
        try Task.checkCancellation()
        try await cache.store(snapshot)
        try Task.checkCancellation()
        return snapshot
    }

    private static func analyzeKitsunebiOffMain(url: URL) async throws -> TobariMeasurement {
        let task = Task.detached(priority: .utility) {
            try KitsunebiAnalyzer.analyze(url: url)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
