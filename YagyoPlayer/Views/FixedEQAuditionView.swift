import SwiftUI

/// iOS 27 device preview for Step 3「一本の耳」.
/// This is a same-track DSP audition, not the two-track A/B flow in 狐火の帳.
struct FixedEQAuditionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlaybackController

    var body: some View {
        FixedEQAuditionPanel(
            state: player.fixedEQAuditionState,
            message: player.fixedEQAuditionMessage,
            onSelect: player.selectFixedEQAuditionMode,
            onClose: { dismiss() }
        )
        .presentationDetents([.height(450), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(YagyoPrintColor.canvas)
    }
}

private struct FixedEQAuditionPanel: View {
    let state: FixedEQAuditionState
    let message: String?
    let onSelect: (FixedEQAuditionMode) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                header
                intro
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
        HStack(alignment: .top, spacing: 12) {
            RetroPlaque(tone: .seal, horizontalPadding: 15, verticalPadding: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "ear")
                        .font(.headline.weight(.semibold))
                    Text("一本の耳")
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .tracking(3)
                        .accessibilityHeading(.h1)
                }
            }

            Spacer()

            RetroIconButton(
                systemImage: "xmark",
                accessibilityLabel: "一本の耳を閉じる",
                shape: .seal,
                action: onClose
            )
        }
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
                    .background(YagyoPrintColor.persimmon, in: Capsule())
                    .overlay(Capsule().stroke(YagyoPrintColor.vermillionInk, lineWidth: 1))
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
        let shape = RoundedRectangle(
            cornerRadius: YagyoPrintMetrics.rowRadius,
            style: .continuous
        )

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
                .background(YagyoPrintColor.vermillionInk, in: RoundedRectangle(cornerRadius: 5))
            Text("この曲だけ・保存されません。Music Understandingによる曲別候補は次の段階です。")
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
            onSelect: { mode = $0 },
            onClose: {}
        )
    }
}
#endif
