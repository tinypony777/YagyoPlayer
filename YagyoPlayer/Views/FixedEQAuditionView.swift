import SwiftUI

/// iOS 27 device preview for Step 3「一本の耳」.
/// This is a same-track DSP audition, not the two-track A/B flow in 狐火の帳.
struct FixedEQAuditionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController
    @StateObject private var featureAnalysis = FeatureAnalysisSession.live()

    private enum AnalysisRequest: Hashable {
        case unavailable(String)
        case analyze(
            trackID: AudioTrack.ID,
            url: URL,
            sourceFingerprint: String
        )
    }

    var body: some View {
        FixedEQAuditionPanel(
            state: player.fixedEQAuditionState,
            message: player.fixedEQAuditionMessage,
            featureAnalysisState: featureAnalysis.state,
            onSelect: player.selectFixedEQAuditionMode,
            onClose: { dismiss() }
        )
        .presentationDetents([.height(570), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(YagyoPrintColor.canvas)
        .task(id: analysisRequest) {
            switch analysisRequest {
            case .unavailable(let message):
                featureAnalysis.markUnavailable(message)
            case .analyze(_, let url, let sourceFingerprint):
                await featureAnalysis.analyze(
                    url: url,
                    sourceFingerprint: sourceFingerprint
                )
            }
        }
    }

    private var analysisRequest: AnalysisRequest {
        guard let currentTrack = player.currentTrack else {
            return .unavailable("曲を読み込むとMusic Understandingで解析できます。")
        }
        let track = library.tracks.first { $0.id == currentTrack.id } ?? currentTrack
        guard let sourceFingerprint = track.contentHash else {
            return .unavailable("解析用の音源識別子を準備しています。")
        }
        return .analyze(
            trackID: track.id,
            url: library.fileURL(for: track),
            sourceFingerprint: sourceFingerprint
        )
    }
}

private struct FixedEQAuditionPanel: View {
    let state: FixedEQAuditionState
    let message: String?
    let featureAnalysisState: FeatureAnalysisSession.State
    let onSelect: (FixedEQAuditionMode) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                header
                intro
                featureAnalysis
                modeChooser
                previewRecipe
                footnote
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(YagyoPrintColor.canvas.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var header: some View {
        WoodblockSectionHeader(
            title: "一本の耳",
            overline: "FIXED EQ AUDITION",
            detail: "iOS 27 · Same-track preview",
            accent: YagyoPrintColor.indigo
        ) {
            RetroIconButton(
                systemImage: "xmark",
                accessibilityLabel: "一本の耳を閉じる",
                shape: .seal,
                action: onClose
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityHeading(.h1)
    }

    private var featureAnalysis: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("曲相")
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.ink)
                Text("MUSIC UNDERSTANDING")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(YagyoPrintColor.vermillionInk)
                Spacer(minLength: 6)
                analysisStatusMark
            }

            switch featureAnalysisState {
            case .idle:
                Text("解析開始を待っています。")
                    .font(.caption)
                    .foregroundStyle(YagyoPrintColor.inkMuted)
                    .accessibilityLabel("Music Understanding解析待機")

            case .analyzing:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(YagyoPrintColor.vermillionInk)
                    Text("この曲を端末内で読み解いています…")
                        .font(.caption)
                        .foregroundStyle(YagyoPrintColor.inkMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Music Understandingで解析中")

            case .ready(let snapshot):
                analysisSummary(snapshot)

            case .unavailable(let reason):
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(YagyoPrintColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modernRetroPanel(tone: .paper, radius: 12, padding: 12)
    }

    @ViewBuilder
    private var analysisStatusMark: some View {
        switch featureAnalysisState {
        case .analyzing:
            Text("解析中")
                .analysisStatusStyle(
                    fill: YagyoPrintColor.persimmon,
                    foreground: YagyoPrintColor.ink,
                    stroke: YagyoPrintColor.ink.opacity(0.35)
                )
        case .ready:
            Text("解析済")
                .analysisStatusStyle(
                    fill: YagyoPrintColor.paperRaised,
                    foreground: YagyoPrintColor.teal,
                    stroke: YagyoPrintColor.teal
                )
        case .idle, .unavailable:
            Text("待機")
                .analysisStatusStyle(
                    fill: YagyoPrintColor.paperMuted,
                    foreground: YagyoPrintColor.ink,
                    stroke: YagyoPrintColor.ink.opacity(0.35)
                )
        }
    }

    private func analysisSummary(_ snapshot: FeatureSnapshot) -> some View {
        let music = snapshot.boundedFiniteFeatures.musicUnderstanding
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                analysisValue(
                    title: "テンポ",
                    value: music.beatsPerMinute.map { String(format: "%.0f BPM", $0) } ?? "—"
                )
                analysisValue(
                    title: "調",
                    value: music.dominantKey.map { "\($0.tonic.uppercased()) \($0.mode)" } ?? "—"
                )
                analysisValue(
                    title: "構成",
                    value: "\(music.sectionCount)幕"
                )
            }

            Text(instrumentSummary(music.instruments))
                .font(.caption2)
                .foregroundStyle(YagyoPrintColor.inkMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(analysisAccessibilityLabel(snapshot))
    }

    private func analysisValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(YagyoPrintColor.inkMuted)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(YagyoPrintColor.teal)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func instrumentSummary(
        _ instruments: [FeatureSnapshot.MusicUnderstandingFeatures.Instrument]
    ) -> String {
        let names = instruments.prefix(3).map(\.identifier)
        return names.isEmpty
            ? "主な音の判定はありません"
            : "主な音  " + names.joined(separator: " · ")
    }

    private func analysisAccessibilityLabel(_ snapshot: FeatureSnapshot) -> String {
        let music = snapshot.boundedFiniteFeatures.musicUnderstanding
        let tempo = music.beatsPerMinute.map { String(format: "%.0f BPM", $0) } ?? "テンポ不明"
        let key = music.dominantKey.map { "\($0.tonic) \($0.mode)" } ?? "調不明"
        return "Music Understanding解析済み、\(tempo)、\(key)、構成、\(music.sectionCount)幕"
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("FIXED EQ · iOS 27 DEVICE PREVIEW")
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(YagyoPrintColor.vermillionInk)
                Spacer(minLength: 6)
                Text("試聴")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(YagyoPrintColor.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(YagyoPrintColor.persimmon, in: WoodblockFrameShape(cut: 5))
                    .overlay(WoodblockFrameShape(cut: 5).stroke(YagyoPrintColor.vermillionInk, lineWidth: 1))
            }

            Text("同じ曲・同じ位置のまま、原音と固定EQの色合いを切り替えます。")
                .font(.footnote)
                .foregroundStyle(YagyoPrintColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeChooser: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.ink)
                Spacer()
                if state.isSwitching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(YagyoPrintColor.vermillionInk)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 10) {
                modeButton(.original, title: "原音", caption: "ORIGINAL")
                modeButton(.fixedEQ, title: "Fixed EQ", caption: "3-BAND")
            }

            Text(statusDetail)
                .font(.caption2)
                .foregroundStyle(message == nil ? YagyoPrintColor.inkMuted : YagyoPrintColor.vermillionInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .modernRetroPanel(tone: .paper, radius: 12, padding: 12)
    }

    private func modeButton(
        _ mode: FixedEQAuditionMode,
        title: String,
        caption: String
    ) -> some View {
        let isRequested = state.requestedMode == mode
        let isApplied = state.appliedMode == mode && !state.isSwitching
        let shape = WoodblockFrameShape(cut: YagyoPrintMetrics.rowRadius)

        return Button {
            onSelect(mode)
        } label: {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(caption)
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                }
                Spacer(minLength: 4)
                Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(YagyoPrintColor.ink)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .padding(.horizontal, 11)
            .background(
                isRequested ? YagyoPrintColor.persimmon : YagyoPrintColor.paperRaised,
                in: shape
            )
            .overlay {
                shape.stroke(
                    isRequested ? YagyoPrintColor.vermillionInk : YagyoPrintColor.paperMuted,
                    lineWidth: isRequested ? 1.5 : 1
                )
                if isRequested {
                    shape
                        .inset(by: 4)
                        .stroke(YagyoPrintColor.paperRaised.opacity(0.8), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(state.availability != .ready)
        .opacity(state.availability == .ready ? 1 : 0.52)
        .accessibilityLabel(title)
        .accessibilityValue(isRequested ? "選択中" : "未選択")
        .accessibilityHint("同じ曲の\(title)へ切り替えます")
    }

    private var previewRecipe: some View {
        VStack(alignment: .leading, spacing: 8) {
            RetroDivider(color: YagyoPrintColor.persimmon)

            HStack(alignment: .firstTextBaseline) {
                Text("試作固定カーブ")
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.ink)
                Spacer()
                Text("音量差補正なし")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.vermillionInk)
            }

            Text("入力余白 −1.0 dB · 180 Hz −0.8 · 1.8 kHz +1.0 · 7.5 kHz −0.6 dB")
                .font(.system(.caption2, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(YagyoPrintColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("仮")
                .font(.caption2.weight(.bold))
                .foregroundStyle(YagyoPrintColor.paperRaised)
                .frame(width: 24, height: 24)
                .background(YagyoPrintColor.vermillionInk, in: WoodblockFrameShape(cut: 5))
            Text("解析結果はこの端末のキャッシュへ保存されます。試聴設定は保存されず、曲別候補は次の段階です。")
                .font(.caption2)
                .foregroundStyle(YagyoPrintColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch state.availability {
        case .unsupported:
            return "この端末では利用できません"
        case .waitingForTrack:
            return "曲を待っています"
        case .ready:
            if state.isSwitching {
                return "\(modeName(state.requestedMode))へ切替中"
            }
            if state.appliesOnNextPlay {
                return "次回再生へ予約済み"
            }
            return "\(modeName(state.appliedMode))を試聴"
        }
    }

    private var statusDetail: String {
        if let message { return message }
        switch state.availability {
        case .unsupported:
            return "従来の再生エンジンが選ばれています。"
        case .waitingForTrack:
            return "夜行または行列で曲を読み込むと切り替えられます。"
        case .ready:
            if state.appliesOnNextPlay {
                return "再生開始と同時に、クリックを避ける短い切替を始めます。"
            }
            return state.isSwitching
                ? "クリックを避ける短い遷移を通しています。"
                : "再生位置を変えずに何度でも戻せます。"
        }
    }

    private var statusColor: Color {
        if message != nil { return YagyoPrintColor.vermillionInk }
        switch state.availability {
        case .unsupported, .waitingForTrack:
            return YagyoPrintColor.paperMuted
        case .ready:
            return state.isSwitching ? YagyoPrintColor.persimmon : YagyoPrintColor.teal
        }
    }

    private func modeName(_ mode: FixedEQAuditionMode) -> String {
        switch mode {
        case .original: "原音"
        case .fixedEQ: "Fixed EQ"
        }
    }
}

#if DEBUG
/// Deterministic visual QA surface; it uses the same panel as the production sheet.
struct FixedEQAuditionPreviewHarness: View {
    @State private var mode = FixedEQAuditionMode.fixedEQ

    var body: some View {
        FixedEQAuditionPanel(
            state: FixedEQAuditionState(
                availability: .ready,
                requestedMode: mode,
                appliedMode: mode,
                isSwitching: false,
                appliesOnNextPlay: false,
                failureMessage: nil
            ),
            message: nil,
            featureAnalysisState: .ready(
                FixedEQAuditionPreviewHarness.previewSnapshot
            ),
            onSelect: { mode = $0 },
            onClose: {}
        )
    }

    private static let previewSnapshot = FeatureSnapshot(
        schemaVersion: FeatureSnapshot.currentSchemaVersion,
        sourceFingerprint: String(repeating: "a", count: 64),
        analyzerVersion: FeatureSnapshot.currentAnalyzerVersion,
        compatibilityKey: FeatureSnapshot.currentCompatibilityKey,
        availability: .complete,
        boundedFiniteFeatures: .init(
            musicUnderstanding: .init(
                beatsPerMinute: 118,
                beatCount: 64,
                barCount: 16,
                meanPace: 0.52,
                sectionCount: 4,
                segmentCount: 8,
                phraseCount: 12,
                silenceSummary: .init(observedSampleCount: 20, silentSampleCount: 2),
                dominantKey: .init(
                    tonic: "a",
                    mode: "minor",
                    observedDurationSeconds: 30
                ),
                instruments: [
                    .init(
                        identifier: "vocal",
                        activeRangeCount: 3,
                        activitySampleCount: 8,
                        meanActivity: 0.78
                    ),
                    .init(
                        identifier: "drum",
                        activeRangeCount: 2,
                        activitySampleCount: 8,
                        meanActivity: 0.64
                    )
                ]
            ),
            kitsunebi: TobariMetrics(
                analyzerVersion: TobariMetrics.currentAnalyzerVersion,
                contentHash: String(repeating: "a", count: 64),
                analyzedAt: Date(timeIntervalSince1970: 1_784_000_000),
                sampleRate: 48_000,
                durationSeconds: 30,
                channelCount: 2,
                integratedLUFS: -18,
                maxShortTermLUFS: -16,
                samplePeakDBFS: -1,
                truePeakDBTP: -0.8,
                clipRunCount: 0,
                clipRunSeconds: [],
                stereoCorrelation: 0.9
            )
        ),
        createdAt: Date(timeIntervalSince1970: 1_784_000_000)
    )
}
#endif

private extension View {
    func analysisStatusStyle(
        fill: Color,
        foreground: Color,
        stroke: Color
    ) -> some View {
        font(.caption2.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
    }
}
