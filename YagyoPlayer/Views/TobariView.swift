import SwiftUI

/// 狐火の帳(Step 5 Phase A) — 一画面検聴。
/// 帳が開いている間は、数値を主役にした生成り紙の開いた台帳として見せる。
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

    /// QA artifact / プレビュー用: 解析せず結果を直接表示する。
    init(presenting metrics: TobariMetrics? = nil) {
        if let metrics {
            started = true
            state = .finished(metrics)
        }
    }

    func start(track: AudioTrack, library: AudioLibraryStore) {
        guard !started else { return }
        started = true

        // 有効なキャッシュがあれば再解析しない(contentHash + analyzerVersion一致)。
        // 重複取込された同一音源(同じcontentHashの別トラック)のキャッシュも共有する。
        let liveTrack = library.tracks.first(where: { $0.id == track.id }) ?? track
        let knownHash = liveTrack.contentHash
        if let cached = liveTrack.tobariMetrics, cached.isValidCache(for: knownHash) {
            state = .finished(cached)
            return
        }
        if let knownHash, let shared = library.sharedTobariMetrics(matching: knownHash) {
            library.storeTobariMetrics(shared, for: track.id)
            state = .finished(shared)
            return
        }

        let url = library.fileURL(for: track)
        state = .analyzing(0)

        // 解析も、旧トラックのhash backfill(ファイル全読みのSHA-256)も、
        // メインスレッドから逃がす。self は強参照: 帳を閉じても解析を完走させ、
        // 結果のキャッシュ保存まで済ませる(コントローラは終了後に解放される)。
        Task.detached(priority: .utility) { [self] in
            do {
                let contentHash = knownHash ?? AudioLibraryStore.computeContentHash(of: url)
                if knownHash == nil, let contentHash {
                    await library.applyBackfilledContentHash(contentHash, for: track.id)
                    // backfillで判明したhashが既存キャッシュと一致するなら解析を省く。
                    if let shared = await library.sharedTobariMetrics(matching: contentHash) {
                        await MainActor.run {
                            library.storeTobariMetrics(shared, for: track.id)
                            self.state = .finished(shared)
                        }
                        return
                    }
                }
                let measurement = try KitsunebiAnalyzer.analyze(url: url) { fraction in
                    Task { @MainActor in
                        if case .analyzing = self.state {
                            self.state = .analyzing(fraction)
                        }
                    }
                }
                await self.finish(
                    measurement: measurement,
                    contentHash: contentHash,
                    trackID: track.id,
                    library: library
                )
            } catch {
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
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
            measurement: measurement,
            contentHash: contentHash
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
    private let presetReference: TobariReferencePreview?

    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController
    @StateObject private var controller: TobariAnalysisController
    @Environment(\.dismiss) private var dismiss

    /// `presetMetrics` / `presetReference` はQA artifact用。
    /// 実ファイルを解析せず、A/Bを含む帳の実描画を固定値で検証する。
    init(
        track: AudioTrack,
        presetMetrics: TobariMetrics? = nil,
        presetReference: TobariReferencePreview? = nil
    ) {
        self.track = track
        self.presetReference = presetReference
        _controller = StateObject(
            wrappedValue: TobariAnalysisController(presenting: presetMetrics)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                recordNote

                switch controller.state {
                case .preparing:
                    progressSection(text: "支度中…", fraction: nil)
                case .analyzing(let fraction):
                    progressSection(text: "狐火が聴き込んでいます…", fraction: fraction)
                case .failed(let message):
                    failureSection(message: message)
                case .finished(let metrics):
                    TobariABComparisonView(
                        subjectTrack: track,
                        subjectMetrics: metrics,
                        presetReference: presetReference
                    )
                    meterLedger(metrics: metrics)
                    findingsSection(metrics: metrics)
                    footnote(metrics: metrics)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(YagyoPrintColor.canvas.ignoresSafeArea())
        .onAppear {
            controller.start(track: track, library: library)
        }
        .onDisappear {
            // 帳の外へ比較用の減衰を持ち出さない。
            player.clearLoudnessMatch()
        }
    }

    private var header: some View {
        WoodblockSectionHeader(
            title: "狐火の帳",
            overline: "ANALYSIS LEDGER",
            detail: "On-device · Read only",
            accent: YagyoPrintColor.vermillionInk
        ) {
            RetroIconButton(
                systemImage: "xmark",
                accessibilityLabel: "帳を閉じる",
                shape: .seal,
                action: { dismiss() }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityHeading(.h1)
    }

    private var recordNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title)
                .font(.headline)
                .foregroundStyle(YagyoPrintColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let artist = track.artist, !artist.isEmpty {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(YagyoPrintColor.inkMuted)
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            TobariDottedRule()
        }
        .accessibilityElement(children: .combine)
    }

    private func progressSection(text: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(YagyoPrintColor.ink)
                .accessibilityHidden(true)

            ProgressView(value: fraction)
                .tint(YagyoPrintColor.teal)
                .accessibilityLabel("解析状況")
                .accessibilityValue(progressAccessibilityValue(text: text, fraction: fraction))

            Text("解析はこの端末の中だけで行われ、再生音と元ファイルは変更されません。")
                .font(.caption2)
                .foregroundStyle(YagyoPrintColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private func failureSection(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(YagyoPrintColor.vermillionInk)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Label("解析できませんでした", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.vermillionInk)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(YagyoPrintColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("再生には影響しません。")
                    .font(.caption2)
                    .foregroundStyle(YagyoPrintColor.inkMuted)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func meterLedger(metrics: TobariMetrics) -> some View {
        let rows: [(name: String, value: String)] = [
            ("Integrated Loudness", metrics.integratedText),
            ("Max Short-term (3s)", metrics.maxShortTermText),
            ("Sample Peak", metrics.samplePeakText),
            ("True Peak (4x)", metrics.truePeakText),
            ("クリップ疑い", metrics.clipText),
            ("モノ互換 (L/R相関)", metrics.monoCompatText)
        ]

        return VStack(alignment: .leading, spacing: 0) {
            TobariDoubleRule()

            Text("狐火の目盛")
                .font(.system(.headline, design: .serif).weight(.semibold))
                .foregroundStyle(YagyoPrintColor.ink)
                .padding(.vertical, 10)
                .accessibilityHeading(.h2)

            ForEach(rows.indices, id: \.self) { index in
                meterRow(rows[index].name, rows[index].value)
                if index < rows.index(before: rows.endIndex) {
                    TobariDottedRule()
                }
            }

            TobariDoubleRule()
        }
    }

    private func meterRow(_ name: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(name)
                    .font(.footnote)
                    .foregroundStyle(YagyoPrintColor.ink)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                metricValue(value)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.footnote)
                    .foregroundStyle(YagyoPrintColor.ink)
                metricValue(value)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(value)
    }

    private func metricValue(_ value: String) -> some View {
        Text(value)
            .font(.system(.footnote, design: .monospaced).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(YagyoPrintColor.teal)
    }

    @ViewBuilder
    private func findingsSection(metrics: TobariMetrics) -> some View {
        let suggestions = metrics.suggestions
        VStack(alignment: .leading, spacing: 14) {
            Text("狐火の見立て")
                .font(.system(.headline, design: .serif).weight(.semibold))
                .foregroundStyle(YagyoPrintColor.ink)
                .accessibilityHeading(.h2)

            if suggestions.isEmpty {
                Text("気になる点はありませんでした。")
                    .font(.footnote)
                    .foregroundStyle(YagyoPrintColor.ink)
            } else {
                ForEach(suggestions.indices, id: \.self) { index in
                    let suggestion = suggestions[index]
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(YagyoPrintColor.paperRaised)
                            .frame(width: 24, height: 24)
                            .background(YagyoPrintColor.vermillionInk, in: Circle())
                            .overlay(Circle().stroke(YagyoPrintColor.vermillion, lineWidth: 1))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 7) {
                            Text(suggestion.text)
                                .font(.footnote)
                                .foregroundStyle(YagyoPrintColor.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(alignment: .top, spacing: 7) {
                                Rectangle()
                                    .fill(YagyoPrintColor.teal)
                                    .frame(width: 2)
                                    .accessibilityHidden(true)
                                Text("根拠: \(suggestion.basis)")
                                    .font(.caption2)
                                    .foregroundStyle(YagyoPrintColor.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("見立て \(index + 1)、\(suggestion.text)")
                    .accessibilityValue("根拠、\(suggestion.basis)")
                }
            }

            Text("提案は自動では適用されません。判断はいつでもあなたのものです。")
                .font(.caption2)
                .foregroundStyle(YagyoPrintColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footnote(metrics: TobariMetrics) -> some View {
        Text(String(
            format: "%.0f Hz / %dch / %@ · ITU-R BS.1770-4準拠のオンデバイス計測",
            metrics.sampleRate,
            metrics.channelCount,
            TobariMetrics.timeText(metrics.durationSeconds)
        ))
        .font(.caption2)
        .foregroundStyle(YagyoPrintColor.inkMuted)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func progressAccessibilityValue(text: String, fraction: Double?) -> String {
        guard let fraction else { return text }
        let percent = Int((min(max(fraction, 0), 1) * 100).rounded())
        return "\(text)、\(percent)パーセント"
    }
}

private struct TobariDoubleRule: View {
    var body: some View {
        VStack(spacing: 3) {
            Rectangle()
                .fill(YagyoPrintColor.teal)
                .frame(height: 1)
            Rectangle()
                .fill(YagyoPrintColor.tealRule)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct TobariDottedRule: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0.5))
            }
            .stroke(
                YagyoPrintColor.tealRule,
                style: StrokeStyle(lineWidth: 1, dash: [2, 3])
            )
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}
