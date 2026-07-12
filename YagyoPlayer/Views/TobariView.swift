import SwiftUI

/// 狐火の帳(Step 5 Phase A) — 一画面検聴。
/// 共存規則(§3): 帳が開いている間は数値が主役で、夜行絵巻は静的な夜空だけが残る。
/// 解析はオフライン・読み取り専用・オンデバイスで、再生音も元ファイルも変更しない。

@MainActor
final class TobariAnalysisController: ObservableObject {
    enum State {
        case preparing
        case analyzing(Double)
        case finished(TobariMetrics)
        case failed(String)
    }

    @Published private(set) var state: State = .preparing

    private var started = false

    func start(track: AudioTrack, library: AudioLibraryStore) {
        guard !started else { return }
        started = true

        // 有効なキャッシュがあれば再解析しない(contentHash + analyzerVersion一致)。
        let contentHash = library.ensureContentHash(for: track.id)
        if let cached = library.tracks.first(where: { $0.id == track.id })?.tobariMetrics,
           cached.isValidCache(for: contentHash) {
            state = .finished(cached)
            return
        }

        let url = library.fileURL(for: track)
        state = .analyzing(0)

        Task.detached(priority: .utility) { [weak self] in
            do {
                let measurement = try KitsunebiAnalyzer.analyze(url: url) { fraction in
                    Task { @MainActor [weak self] in
                        if case .analyzing = self?.state {
                            self?.state = .analyzing(fraction)
                        }
                    }
                }
                await self?.finish(
                    measurement: measurement,
                    contentHash: contentHash,
                    trackID: track.id,
                    library: library
                )
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func finish(
        measurement: TobariMeasurement,
        contentHash: String?,
        trackID: AudioTrack.ID,
        library: AudioLibraryStore
    ) {
        let metrics = TobariMetrics(
            analyzerVersion: TobariMetrics.currentAnalyzerVersion,
            contentHash: contentHash,
            analyzedAt: Date(),
            sampleRate: measurement.sampleRate,
            durationSeconds: measurement.durationSeconds,
            channelCount: measurement.channelCount,
            integratedLUFS: measurement.integratedLUFS,
            maxShortTermLUFS: measurement.maxShortTermLUFS,
            samplePeakDBFS: measurement.samplePeakDBFS,
            truePeakDBTP: measurement.truePeakDBTP,
            clipRunCount: measurement.clipRunCount,
            clipRunSeconds: measurement.clipRunSeconds,
            stereoCorrelation: measurement.stereoCorrelation
        )
        // hashをbackfillできなかった音源はキャッシュせず、今回の表示だけに使う(仕様 §4.1)。
        if contentHash != nil {
            library.storeTobariMetrics(metrics, for: trackID)
        }
        state = .finished(metrics)
    }
}

struct TobariView: View {
    let track: AudioTrack

    @EnvironmentObject private var library: AudioLibraryStore
    @StateObject private var controller = TobariAnalysisController()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 静的な夜空。絵巻(行列)は帳の間は退場する。
            LinearGradient(
                colors: [Color(yagyoHex: 0x070812), Color(yagyoHex: 0x10131f)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    switch controller.state {
                    case .preparing:
                        progressPanel(text: "支度中…", fraction: nil)
                    case .analyzing(let fraction):
                        progressPanel(text: "狐火が聴き込んでいます…", fraction: fraction)
                    case .failed(let message):
                        failurePanel(message: message)
                    case .finished(let metrics):
                        meterPanel(metrics: metrics)
                        suggestionPanel(metrics: metrics)
                        footnote(metrics: metrics)
                    }
                }
                .padding(18)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            controller.start(track: track, library: library)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("狐火の帳")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(YagyoColor.kitsunebi)
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YagyoColor.geppaku)
                    .lineLimit(2)
                if let artist = track.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(YagyoColor.dim)
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(YagyoColor.dim)
            }
            .accessibilityLabel("帳を閉じる")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("狐火の帳、\(track.title)")
    }

    private func progressPanel(text: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(YagyoColor.geppaku)
            ProgressView(value: fraction)
                .tint(YagyoColor.kitsunebi)
            Text("解析はこの端末の中だけで行われ、再生音と元ファイルは変更されません。")
                .font(.caption2)
                .foregroundStyle(YagyoColor.dim)
        }
        .ritualPanel(radius: 20, padding: 16, tint: YagyoColor.kitsunebi.opacity(0.06))
        .accessibilityElement(children: .combine)
    }

    private func failurePanel(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("解析できませんでした", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(YagyoColor.shu)
            Text(message)
                .font(.caption)
                .foregroundStyle(YagyoColor.dim)
            Text("再生には影響しません。")
                .font(.caption2)
                .foregroundStyle(YagyoColor.dim)
        }
        .ritualPanel(radius: 20, padding: 16, tint: YagyoColor.shu.opacity(0.08))
        .accessibilityElement(children: .combine)
    }

    private func meterPanel(metrics: TobariMetrics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("狐火の目盛")
                .font(.caption.weight(.semibold))
                .foregroundStyle(YagyoColor.dim)
                .padding(.bottom, 6)

            meterRow("Integrated Loudness", metrics.integratedText)
            meterRow("Max Short-term (3s)", metrics.maxShortTermText)
            meterRow("Sample Peak", metrics.samplePeakText)
            meterRow("True Peak (4x)", metrics.truePeakText)
            meterRow("クリップ疑い", metrics.clipText)
            meterRow("モノ互換 (L/R相関)", metrics.monoCompatText)
        }
        .ritualPanel(radius: 20, padding: 16, tint: YagyoColor.kitsunebi.opacity(0.06))
    }

    private func meterRow(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(.footnote)
                .foregroundStyle(YagyoColor.geppaku)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(YagyoColor.kitsunebi)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name)、\(value)")
    }

    @ViewBuilder
    private func suggestionPanel(metrics: TobariMetrics) -> some View {
        let suggestions = metrics.suggestions
        VStack(alignment: .leading, spacing: 10) {
            Text("提案")
                .font(.caption.weight(.semibold))
                .foregroundStyle(YagyoColor.dim)

            if suggestions.isEmpty {
                Text("気になる点はありませんでした。")
                    .font(.footnote)
                    .foregroundStyle(YagyoColor.geppaku)
            } else {
                ForEach(suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(suggestion.text)
                            .font(.footnote)
                            .foregroundStyle(YagyoColor.geppaku)
                        Text("根拠: \(suggestion.basis)")
                            .font(.caption2)
                            .foregroundStyle(YagyoColor.chochin)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Text("提案は自動では適用されません。判断はいつでもあなたのものです。")
                .font(.caption2)
                .foregroundStyle(YagyoColor.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ritualPanel(radius: 20, padding: 16)
    }

    private func footnote(metrics: TobariMetrics) -> some View {
        Text(String(
            format: "%.0f Hz / %dch / %@ · ITU-R BS.1770-4準拠のオンデバイス計測",
            metrics.sampleRate,
            metrics.channelCount,
            TobariMetrics.timeText(metrics.durationSeconds)
        ))
        .font(.caption2)
        .foregroundStyle(YagyoColor.footerInk)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
