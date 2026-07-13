import SwiftUI

/// QA artifact用の固定参照。通常利用ではライブラリ内のトラックと解析キャッシュを使う。
struct TobariReferencePreview: Sendable {
    let track: AudioTrack
    let metrics: TobariMetrics
}

/// 狐火の帳 Phase B — 参照音源の選択とA/B検聴の入口。
struct TobariABComparisonView: View {
    let subjectTrack: AudioTrack
    let subjectMetrics: TobariMetrics
    let presetReference: TobariReferencePreview?

    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController
    @State private var referenceTrackID: AudioTrack.ID?

    init(
        subjectTrack: AudioTrack,
        subjectMetrics: TobariMetrics,
        presetReference: TobariReferencePreview? = nil
    ) {
        self.subjectTrack = subjectTrack
        self.subjectMetrics = subjectMetrics
        self.presetReference = presetReference
        _referenceTrackID = State(initialValue: presetReference?.track.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("A/B検聴")
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.ink)
                    .accessibilityHeading(.h2)
                Spacer()
                Text("減衰のみ")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.vermillionInk)
            }

            if referenceTracks.isEmpty {
                Text("参照に使える別の音源がありません。行列へもう1曲加えると比較できます。")
                    .font(.footnote)
                    .foregroundStyle(YagyoPrintColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                referenceMenu

                if let referenceTrack {
                    TobariABPairView(
                        subjectTrack: subjectTrack,
                        subjectMetrics: subjectMetrics,
                        referenceTrack: referenceTrack,
                        presetReferenceMetrics: presetMetrics(for: referenceTrack)
                    )
                    .id(referenceTrack.id)
                } else {
                    Text("参照音源を選ぶと、同じ時刻を保ったままA/Bを切り替えられます。")
                        .font(.footnote)
                        .foregroundStyle(YagyoPrintColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .modernRetroPanel(tone: .paper, radius: 12, padding: 14)
        .onChange(of: referenceTrackID) { _, _ in
            // 参照変更時に、前の組み合わせの減衰を残さない。
            player.clearLoudnessMatch()
        }
    }

    private var referenceMenu: some View {
        Menu {
            ForEach(referenceTracks) { track in
                Button {
                    referenceTrackID = track.id
                } label: {
                    if track.id == referenceTrackID {
                        Label(track.title, systemImage: "checkmark")
                    } else {
                        Text(track.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("参照音源 B")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(YagyoPrintColor.inkMuted)
                    Text(referenceTrack?.title ?? "選んでください")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(YagyoPrintColor.ink)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.vermillionInk)
            }
            .frame(minHeight: YagyoPrintMetrics.controlHitTarget)
            .padding(.horizontal, 12)
            .background(
                YagyoPrintColor.paperRaised,
                in: RoundedRectangle(cornerRadius: YagyoPrintMetrics.rowRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: YagyoPrintMetrics.rowRadius, style: .continuous)
                    .stroke(YagyoPrintColor.ink, lineWidth: YagyoPrintMetrics.ruleWidth)
            }
        }
        .accessibilityLabel("参照音源 B")
        .accessibilityValue(referenceTrack?.title ?? "未選択")
    }

    private var referenceTracks: [AudioTrack] {
        var tracks = library.tracks.filter { $0.id != subjectTrack.id }
        if let preview = presetReference,
           preview.track.id != subjectTrack.id,
           !tracks.contains(where: { $0.id == preview.track.id }) {
            tracks.insert(preview.track, at: 0)
        }
        return tracks
    }

    private var referenceTrack: AudioTrack? {
        guard let referenceTrackID else { return nil }
        return referenceTracks.first { $0.id == referenceTrackID }
    }

    private func presetMetrics(for track: AudioTrack) -> TobariMetrics? {
        guard presetReference?.track.id == track.id else { return nil }
        return presetReference?.metrics
    }
}

private struct TobariABPairView: View {
    let subjectTrack: AudioTrack
    let subjectMetrics: TobariMetrics
    let referenceTrack: AudioTrack

    @EnvironmentObject private var library: AudioLibraryStore
    @EnvironmentObject private var player: PlaybackController
    @StateObject private var referenceController: TobariAnalysisController
    @State private var activeSide = TobariABSide.subject

    init(
        subjectTrack: AudioTrack,
        subjectMetrics: TobariMetrics,
        referenceTrack: AudioTrack,
        presetReferenceMetrics: TobariMetrics? = nil
    ) {
        self.subjectTrack = subjectTrack
        self.subjectMetrics = subjectMetrics
        self.referenceTrack = referenceTrack
        _referenceController = StateObject(
            wrappedValue: TobariAnalysisController(presenting: presetReferenceMetrics)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            referenceAnalysisStatus
            sideChooser
            playbackControl
            matchControl
        }
        .onAppear {
            referenceController.start(track: referenceTrack, library: library)
        }
        .onChange(of: player.currentTrack?.id) { _, currentTrackID in
            if player.isLoudnessMatchActive,
               currentTrackID != track(for: activeSide).id {
                player.clearLoudnessMatch()
            }
        }
        .onDisappear {
            player.clearLoudnessMatch()
        }
    }

    @ViewBuilder
    private var referenceAnalysisStatus: some View {
        switch referenceController.state {
        case .preparing:
            compactStatus("参照音源を支度中…", progress: nil)
        case .analyzing(let fraction):
            compactStatus("参照音源を解析中…", progress: fraction)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 3) {
                Text("ラウドネスマッチは使えません")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YagyoPrintColor.vermillionInk)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(YagyoPrintColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .finished:
            EmptyView()
        }
    }

    private func compactStatus(_ text: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.caption)
                .foregroundStyle(YagyoPrintColor.inkMuted)
            ProgressView(value: progress)
                .tint(YagyoPrintColor.persimmon)
                .accessibilityLabel(text)
        }
    }

    private var sideChooser: some View {
        HStack(spacing: 10) {
            sideButton(.subject, track: subjectTrack, metrics: subjectMetrics)
            sideButton(.reference, track: referenceTrack, metrics: referenceMetrics)
        }
    }

    private func sideButton(
        _ side: TobariABSide,
        track: AudioTrack,
        metrics: TobariMetrics?
    ) -> some View {
        let isActive = activeSide == side
        let letter = side == .subject ? "A" : "B"
        let loudness = metrics?.integratedText ?? "解析待ち"

        return Button {
            select(side)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(letter)
                        .font(.system(.title3, design: .serif).weight(.bold))
                    Spacer()
                    if isActive {
                        Image(systemName: "record.circle.fill")
                            .font(.caption)
                    }
                }
                Text(track.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(loudness)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(YagyoPrintColor.ink)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(10)
            .background(
                isActive ? YagyoPrintColor.persimmon : YagyoPrintColor.paperRaised,
                in: RoundedRectangle(cornerRadius: YagyoPrintMetrics.rowRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: YagyoPrintMetrics.rowRadius, style: .continuous)
                    .stroke(
                        isActive ? YagyoPrintColor.vermillionInk : YagyoPrintColor.paperMuted,
                        lineWidth: isActive ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(letter)、\(track.title)")
        .accessibilityValue("\(isActive ? "選択中" : "未選択")、\(loudness)")
        .accessibilityHint("この音源へ切り替えます")
    }

    private var playbackControl: some View {
        Button(action: togglePlayback) {
            HStack(spacing: 10) {
                Image(systemName: isActiveSidePlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
                Text(isActiveSidePlaying ? "比較を一時停止" : "選択中の音源を再生")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if player.currentTrack?.id == track(for: activeSide).id {
                    Text("\(player.elapsedText) / \(player.durationText)")
                        .font(.system(.caption2, design: .monospaced))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(YagyoPrintColor.paperRaised)
            .frame(minHeight: YagyoPrintMetrics.controlHitTarget)
            .padding(.horizontal, 12)
            .background(
                YagyoPrintColor.ink,
                in: RoundedRectangle(cornerRadius: YagyoPrintMetrics.rowRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var matchControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            RetroDivider(color: YagyoPrintColor.persimmon)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isMatchActive ? "ラウドネスマッチ適用中" : "マッチなし")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isMatchActive ? YagyoPrintColor.vermillionInk : YagyoPrintColor.ink)
                    Text(matchStatusText)
                        .font(.system(.caption2, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(YagyoPrintColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: toggleMatch) {
                    Text(isMatchActive ? "マッチなしへ" : "音量差を揃える")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(YagyoPrintColor.ink)
                        .frame(minHeight: YagyoPrintMetrics.controlHitTarget)
                        .padding(.horizontal, 10)
                        .background(
                            isMatchActive ? YagyoPrintColor.persimmon : YagyoPrintColor.paperRaised,
                            in: RoundedRectangle(cornerRadius: YagyoPrintMetrics.rowRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: YagyoPrintMetrics.rowRadius, style: .continuous)
                                .stroke(YagyoPrintColor.vermillionInk, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!canToggleMatch)
                .opacity(canToggleMatch ? 1 : 0.5)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var referenceMetrics: TobariMetrics? {
        guard case .finished(let metrics) = referenceController.state else { return nil }
        return metrics
    }

    private var loudnessMatch: TobariLoudnessMatch? {
        TobariLoudnessMatch(
            subjectIntegratedLUFS: subjectMetrics.integratedLUFS,
            referenceIntegratedLUFS: referenceMetrics?.integratedLUFS
        )
    }

    private var matchStatusText: String {
        guard let loudnessMatch else {
            return "Integrated Loudnessの計測待ち、または計測不能"
        }
        let a = Self.gainText(loudnessMatch.subjectGainDB)
        let b = Self.gainText(loudnessMatch.referenceGainDB)
        guard isActiveSideLoaded else {
            return "適用候補 A \(a) / B \(b) · 選択中の音源を先に再生"
        }
        return isMatchActive
            ? "適用量 A \(a) / B \(b)"
            : "適用候補 A \(a) / B \(b)"
    }

    private var isActiveSidePlaying: Bool {
        isActiveSideLoaded && player.isPlaying
    }

    private var isActiveSideLoaded: Bool {
        pair.canApply(to: player.currentTrack?.id, activeSide: activeSide)
    }

    private var canToggleMatch: Bool {
        loudnessMatch != nil && isActiveSideLoaded
    }

    private var isMatchActive: Bool {
        player.isLoudnessMatchActive && isActiveSideLoaded
    }

    private var pair: TobariABPair {
        TobariABPair(
            subjectTrackID: subjectTrack.id,
            referenceTrackID: referenceTrack.id
        )
    }

    private func track(for side: TobariABSide) -> AudioTrack {
        switch side {
        case .subject:
            subjectTrack
        case .reference:
            referenceTrack
        }
    }

    private func select(_ side: TobariABSide) {
        let currentTrackID = player.currentTrack?.id
        let resumeTime = pair.contains(currentTrackID) ? player.currentPlaybackTime : 0
        let shouldResume = player.isPlaying
        let shouldPreserveMatch = isMatchActive
        let target = track(for: side)

        activeSide = side
        guard currentTrackID != target.id else {
            return
        }

        // loadは乗数を必ず解除する。再生前に選択側の乗数を再適用し、
        // 音量が一瞬だけ跳ねることを避ける。
        player.load(target, from: library, autoplay: false, context: .library)
        guard player.currentTrack?.id == target.id else { return }
        if resumeTime > 0 {
            player.seek(to: resumeTime)
        }
        applyCurrentMatch(enabled: shouldPreserveMatch)
        if shouldResume {
            player.play()
        }
    }

    private func togglePlayback() {
        let target = track(for: activeSide)
        if player.currentTrack?.id == target.id {
            if player.isPlaying {
                player.pause()
            } else {
                player.play()
            }
            return
        }

        player.load(target, from: library, autoplay: false, context: .library)
        guard player.currentTrack?.id == target.id else { return }
        player.play()
    }

    private func toggleMatch() {
        if isMatchActive {
            player.clearLoudnessMatch()
            return
        }
        applyCurrentMatch(enabled: true)
    }

    private func applyCurrentMatch(enabled: Bool) {
        guard enabled, isActiveSideLoaded, let loudnessMatch else {
            player.clearLoudnessMatch()
            return
        }
        player.setLoudnessMatchMultiplier(loudnessMatch.multiplier(for: activeSide))
    }

    private static func gainText(_ gainDB: Double) -> String {
        String(format: "%.1f dB", abs(gainDB) < 0.05 ? 0.0 : gainDB)
    }
}
