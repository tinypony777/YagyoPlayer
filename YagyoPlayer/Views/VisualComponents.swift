import SwiftUI

struct YagyoBackdrop: View {
    var isUshimitsu: Bool

    var body: some View {
        ZStack {
            YagyoPrintColor.canvas
                .ignoresSafeArea()

            // 丑三つ時も紙面全体は暗転させず、ごく薄い朱の刷りだけを重ねる。
            YagyoPrintColor.vermillion
                .opacity(isUshimitsu ? 0.025 : 0)
                .ignoresSafeArea()

            Canvas { context, size in
                // ラスターを使わない、決定論的な紙の繊維。装飾なので3%以下に抑える。
                for index in 0..<64 {
                    let seed = Double(index)
                    let x = Self.fract(sin(seed * 12.9898) * 43758.5453) * size.width
                    let y = Self.fract(sin(seed * 78.233) * 12543.123) * size.height
                    let side = index.isMultiple(of: 5) ? 1.4 : 0.8
                    context.fill(
                        Path(CGRect(x: x, y: y, width: side, height: side)),
                        with: .color(YagyoPrintColor.ink.opacity(0.018))
                    )
                }

                for index in 0..<14 {
                    let seed = Double(index + 80)
                    let x = Self.fract(sin(seed * 19.913) * 15731.743) * size.width
                    let y = Self.fract(sin(seed * 47.853) * 31871.411) * size.height
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: min(size.width, x + 7), y: y + CGFloat(index % 2)))
                    context.stroke(
                        path,
                        with: .color(YagyoPrintColor.inkMuted.opacity(0.025)),
                        lineWidth: 0.7
                    )
                }

                // 浮世絵の霞。静止した低濃度の版として、紙の余白を分割する。
                for index in 0..<3 {
                    let y = size.height * (0.16 + CGFloat(index) * 0.28)
                    let startsOnRight = index.isMultiple(of: 2)
                    let leading = startsOnRight ? size.width * 0.62 : -size.width * 0.08
                    let width = size.width * (startsOnRight ? 0.48 : 0.42)
                    var kasumi = Path()
                    kasumi.move(to: CGPoint(x: leading, y: y))
                    kasumi.addLine(to: CGPoint(x: leading + width, y: y))
                    kasumi.addLine(to: CGPoint(x: leading + width - 18, y: y + 8))
                    kasumi.addLine(to: CGPoint(x: leading + 8, y: y + 8))
                    kasumi.closeSubpath()
                    context.fill(
                        kasumi,
                        with: .color(
                            (index == 1 ? YagyoPrintColor.vermillion : YagyoPrintColor.persimmon)
                                .opacity(index == 1 ? 0.070 : 0.052)
                        )
                    )
                }

                // 版画の丸紋。情報面を塗り潰さず、背景へ色版があることは見える濃度にする。
                let monCenter = CGPoint(x: size.width * 0.84, y: size.height * 0.12)
                let monRadius = min(size.width * 0.13, 58)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: monCenter.x - monRadius,
                        y: monCenter.y - monRadius,
                        width: monRadius * 2,
                        height: monRadius * 2
                    )),
                    with: .color(YagyoPrintColor.persimmon.opacity(0.060))
                )
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: monCenter.x - monRadius,
                        y: monCenter.y - monRadius,
                        width: monRadius * 2,
                        height: monRadius * 2
                    )),
                    with: .color(YagyoPrintColor.vermillion.opacity(0.10)),
                    lineWidth: 1
                )

                // 画面下端の青海波。情報面へ干渉しないよう線だけを薄く刷る。
                let waveRadius = max(18, size.width / 11)
                for row in 0..<2 {
                    for column in -1...7 {
                        let offset = row.isMultiple(of: 2) ? 0.0 : waveRadius
                        let center = CGPoint(
                            x: CGFloat(column) * waveRadius * 2 + offset,
                            y: size.height - CGFloat(row) * waveRadius * 0.58
                        )
                        var wave = Path()
                        wave.addArc(
                            center: center,
                            radius: waveRadius,
                            startAngle: .degrees(180),
                            endAngle: .degrees(360),
                            clockwise: false
                        )
                        context.stroke(
                            wave,
                            with: .color(YagyoPrintColor.indigo.opacity(0.080)),
                            lineWidth: 0.9
                        )
                    }
                }
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 1.2), value: isUshimitsu)
    }

    private static func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}

/// 短い外題を一字ずつ積む。Accessibility Dynamic Typeでは通常の横書きへ戻す。
struct VerticalTitleColumn: View {
    let title: String
    var accent: Color = YagyoPrintColor.vermillionInk

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text(title)
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .tracking(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(title.enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                    }
                }
                .font(.system(.headline, design: .serif).weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 10)
            }
        }
        .foregroundStyle(YagyoPrintColor.paperRaised)
        .background(accent, in: WoodblockFrameShape(cut: 6))
        .overlay {
            let shape = WoodblockFrameShape(cut: 6)
            shape.stroke(YagyoPrintColor.indigo, lineWidth: 1.5)
            shape
                .inset(by: 3)
                .stroke(YagyoPrintColor.paperRaised.opacity(0.72), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// 行列・巻物などの上端を、縦外題と現代的な編集情報へ分ける共通見出し。
struct WoodblockSectionHeader<Trailing: View>: View {
    let title: String
    let overline: String
    let detail: String
    var accent: Color = YagyoPrintColor.vermillionInk
    private let trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        overline: String,
        detail: String,
        accent: Color = YagyoPrintColor.vermillionInk,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.overline = overline
        self.detail = detail
        self.accent = accent
        self.trailing = trailing
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        VerticalTitleColumn(title: title, accent: accent)
                        Spacer(minLength: 8)
                        trailing()
                            .fixedSize()
                    }

                    headerDetails
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VerticalTitleColumn(title: title, accent: accent)
                    headerDetails
                        .padding(.top, 4)

                    Spacer(minLength: 8)
                    trailing()
                        .fixedSize()
                }
            }
        }
    }

    private var headerDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(overline)
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(YagyoPrintColor.paperRaised)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(accent, in: WoodblockFrameShape(cut: 5))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(YagyoPrintColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 欄外注 — 一枚摺の余白へ直接刷る但し書き。パネルへ閉じ込めず、
/// 夜行・行列・巻物で同じ「注」の語り口を共有する。
struct RetroMarginalNote: View {
    var text: String
    var alignment: Alignment = .trailing

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .serif))
            .tracking(1.4)
            .foregroundStyle(YagyoPrintColor.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

/// 横長の「音の足跡」が引き継ぐ表示状態。
/// 入力は全曲波形ではなく、既存の局所正規化された15 Hz表示信号である。
enum WoodblockWaveformPresentation: Equatable, Sendable {
    case stopped
    case unavailable
    case low
    case medium
    case high

    init(
        activity: ParadeSignalSnapshot.Activity,
        levelBand: ParadeSignalSnapshot.LevelBand
    ) {
        switch activity {
        case .stopped:
            self = .stopped
        case .unavailable:
            self = .unavailable
        case .quietProxy, .normal:
            switch levelBand {
            case .unavailable:
                self = .unavailable
            case .low:
                self = .low
            case .medium:
                self = .medium
            case .high:
                self = .high
            }
        }
    }

    var usesAccentColor: Bool {
        switch self {
        case .stopped, .unavailable:
            false
        case .low, .medium, .high:
            true
        }
    }

    var centerMark: String {
        switch self {
        case .stopped: "止"
        case .unavailable: "—"
        case .low: "静"
        case .medium: "響"
        case .high: "烈"
        }
    }

    var accessibilityState: String {
        switch self {
        case .stopped: "停止"
        case .unavailable: "利用不可"
        case .low: "静か"
        case .medium: "中程度"
        case .high: "強い"
        }
    }

    var fallbackLevel: Double {
        switch self {
        case .stopped: 0.16
        case .unavailable: 0.28
        case .low: 0.24
        case .medium: 0.54
        case .high: 0.86
        }
    }
}

/// 版木枠の横一本「音の足跡」。直近の表示信号だけを固定上限で保持する。
/// 曲全体のpeak/RMS列を装わず、再生位置は画面下の短冊目盛に任せる。
struct WoodblockWaveform: View {
    var level: Double = 0
    var activity: ParadeSignalSnapshot.Activity
    var levelBand: ParadeSignalSnapshot.LevelBand
    var history = WaveformHistoryBuffer()
    var title: String? = nil
    var artist: String? = nil
    var guardianImage: Image? = nil
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        let presentation = WoodblockWaveformPresentation(
            activity: activity,
            levelBand: levelBand
        )

        GeometryReader { _ in
            let shape = WoodblockFrameShape(cut: 10)

            ZStack {
                Canvas { context, size in
                    let horizontalInset: CGFloat = 16
                    let topInset: CGFloat = 30
                    let waveformBottom = size.height - metadataHeight - 10
                    let centerY = topInset + (waveformBottom - topInset) * 0.5
                    let availableHeight = max(12, waveformBottom - topInset)
                    let count = max(32, min(84, Int((size.width - horizontalInset * 2) / 4)))
                    let levels = sampledLevels(count: count, fallback: presentation.fallbackLevel)
                    let spacing = (size.width - horizontalInset * 2) / CGFloat(max(count - 1, 1))

                    let sunRadius = min(size.height * 0.32, 52)
                    let sunCenter = CGPoint(x: size.width * 0.78, y: centerY)
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: sunCenter.x - sunRadius,
                            y: sunCenter.y - sunRadius,
                            width: sunRadius * 2,
                            height: sunRadius * 2
                        )),
                        with: .color(YagyoPrintColor.persimmon.opacity(0.12))
                    )

                    for waveIndex in 0..<7 {
                        let radius = max(12, size.width / 18)
                        let center = CGPoint(
                            x: CGFloat(waveIndex) * radius * 2 - radius * 0.4,
                            y: waveformBottom + radius * 0.46
                        )
                        var wave = Path()
                        wave.addArc(
                            center: center,
                            radius: radius,
                            startAngle: .degrees(180),
                            endAngle: .degrees(360),
                            clockwise: false
                        )
                        context.stroke(
                            wave,
                            with: .color(YagyoPrintColor.indigo.opacity(0.10)),
                            lineWidth: 0.8
                        )
                    }

                    var centerRule = Path()
                    centerRule.move(to: CGPoint(x: horizontalInset, y: centerY))
                    centerRule.addLine(to: CGPoint(x: size.width - horizontalInset, y: centerY))
                    context.stroke(
                        centerRule,
                        with: .color(YagyoPrintColor.vermillion.opacity(0.48)),
                        lineWidth: 0.9
                    )

                    for index in 0..<count {
                        if presentation == .unavailable, !index.isMultiple(of: 4) { continue }
                        let normalizedLevel = min(max(levels[index], 0), 1)
                        let hierarchy = index.isMultiple(of: 12) ? 4.0 : (index.isMultiple(of: 4) ? 2.0 : 0.0)
                        let halfHeight = max(
                            3,
                            min(availableHeight * 0.46, 4 + CGFloat(normalizedLevel) * availableHeight * 0.38 + hierarchy)
                        )
                        let x = horizontalInset + CGFloat(index) * spacing
                        var bar = Path()
                        bar.move(to: CGPoint(x: x, y: centerY - halfHeight))
                        bar.addLine(to: CGPoint(x: x, y: centerY + halfHeight))

                        let isNewest = index == count - 1 && presentation.usesAccentColor
                        let barColor = isNewest
                            ? YagyoPrintColor.persimmon
                            : (presentation == .high && index.isMultiple(of: 12)
                                ? YagyoPrintColor.vermillionInk
                                : YagyoPrintColor.indigo)
                        context.stroke(
                            bar,
                            with: .color(barColor.opacity(lineOpacity(for: presentation))),
                            lineWidth: index.isMultiple(of: 12) ? 2 : 1
                        )
                    }

                }

                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        Text("直近の音")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.5)
                            .foregroundStyle(YagyoPrintColor.paperRaised)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(YagyoPrintColor.indigo, in: WoodblockFrameShape(cut: 4))
                        Spacer()
                        Text(presentation.centerMark)
                            .font(.system(.caption, design: .serif).weight(.bold))
                            .foregroundStyle(YagyoPrintColor.paperRaised)
                            .frame(width: 26, height: 26)
                            .background(
                                presentation.usesAccentColor
                                    ? YagyoPrintColor.vermillionInk
                                    : YagyoPrintColor.indigo,
                                in: WoodblockFrameShape(cut: 5)
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

                    if let title {
                        Rectangle()
                            .fill(YagyoPrintColor.paperMuted)
                            .frame(height: YagyoPrintMetrics.ruleWidth)

                        HStack(spacing: 10) {
                            if let guardianImage {
                                guardianImage
                                    .resizable()
                                    .scaledToFit()
                                    .padding(3)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        YagyoPrintColor.brass.opacity(0.22),
                                        in: WoodblockFrameShape(cut: 5)
                                    )
                                    .overlay {
                                        WoodblockFrameShape(cut: 5)
                                            .stroke(YagyoPrintColor.vermillionInk, lineWidth: 1)
                                    }
                                    .accessibilityHidden(true)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(YagyoPrintColor.ink)
                                    .lineLimit(1)

                                if let artist, !artist.isEmpty {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundStyle(YagyoPrintColor.inkMuted)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 8)

                            Text("音")
                                .font(.system(.caption, design: .serif).weight(.bold))
                                .foregroundStyle(YagyoPrintColor.paperRaised)
                                .frame(width: 26, height: 26)
                                .background(YagyoPrintColor.indigo, in: WoodblockFrameShape(cut: 5))
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 10 : 0)
                        .frame(height: metadataHeight - YagyoPrintMetrics.ruleWidth)
                        .background(YagyoPrintColor.persimmon.opacity(0.11))
                    }
                }
            }
            .background(YagyoPrintColor.paperRaised, in: shape)
            .clipShape(shape)
            .overlay {
                shape.stroke(YagyoPrintColor.indigo, lineWidth: 2)
                shape
                    .inset(by: YagyoPrintMetrics.innerRuleInset)
                    .stroke(YagyoPrintColor.vermillion.opacity(0.72), lineWidth: 1)
            }
        }
        .frame(minHeight: 112)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(for: presentation))
    }

    private func sampledLevels(count: Int, fallback: Double) -> [Double] {
        guard !reduceMotion else {
            return Array(repeating: fallback, count: max(1, count))
        }
        return history.sampled(count: count, fallback: fallback)
    }

    private var metadataHeight: CGFloat {
        guard title != nil else { return 0 }
        return dynamicTypeSize.isAccessibilitySize ? 132 : 48
    }

    private func lineOpacity(for presentation: WoodblockWaveformPresentation) -> Double {
        switch presentation {
        case .stopped:
            0.55
        case .unavailable:
            0.70
        case .low:
            reduceMotion ? 0.68 : 0.86
        case .medium:
            reduceMotion ? 0.78 : 0.90
        case .high:
            0.95
        }
    }

    private func accessibilityDescription(for presentation: WoodblockWaveformPresentation) -> String {
        let state = "直近の音、\(presentation.accessibilityState)"
        guard let title else { return state }
        if let artist, !artist.isEmpty {
            return "\(title)、\(artist)。\(state)"
        }
        return "\(title)。\(state)"
    }

}

/// 16本の短冊目盛による再生位置。過ぎた目盛は朱、現在位置は柿色で示す。
/// 短冊は名のとおり縦長の紙片にし、幅は固定・間だけを画面幅で伸縮させる。
struct StepProgressBar: View {
    var progress: Double
    var isEnabled: Bool
    var onScrub: (Double) -> Void

    private let steps = 16
    private let groupGap: CGFloat = 8
    /// 短冊一枚の幅。これより広げず、余りは目と目の間へ配る。
    private let cellWidthLimit: CGFloat = 9
    private let minSpacing: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let cellWidth = max(
                2,
                min(
                    cellWidthLimit,
                    (width - groupGap * 3 - minSpacing * CGFloat(steps - 1)) / CGFloat(steps)
                )
            )
            let spacing = max(
                minSpacing,
                (width - cellWidth * CGFloat(steps) - groupGap * 3) / CGFloat(steps - 1)
            )
            HStack(spacing: spacing) {
                ForEach(0..<steps, id: \.self) { index in
                    cell(at: index)
                        .frame(width: cellWidth, height: index.isMultiple(of: 4) ? 21 : 15)
                        .padding(.leading, index % 4 == 0 && index > 0 ? groupGap : 0)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard isEnabled else { return }
                onScrub(fraction(at: location.x, cellWidth: cellWidth, spacing: spacing))
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        onScrub(fraction(at: value.location.x, cellWidth: cellWidth, spacing: spacing))
                    },
                including: isEnabled ? .all : .subviews
            )
        }
        // 短冊の見た目は15/21ptのまま、scrub操作面だけを44pt確保する。
        .frame(height: YagyoPrintMetrics.controlHitTarget)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement()
        .accessibilityLabel("再生位置")
        .accessibilityValue("\(Int(progress * 100))パーセント")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let delta = direction == .increment ? 0.05 : -0.05
            onScrub(min(max(progress + delta, 0), 1))
        }
    }

    /// タップ/ドラッグ位置をセル配置(伸縮する目 + 拍頭8ptの間)に沿って割合へ写す。
    private func fraction(at x: CGFloat, cellWidth: CGFloat, spacing: CGFloat) -> Double {
        var start: CGFloat = 0
        for index in 0..<steps {
            if index > 0 {
                start += spacing
                if index % 4 == 0 { start += groupGap }
            }
            let end = start + cellWidth
            if x < end || index == steps - 1 {
                let within = min(max((x - start) / cellWidth, 0), 1)
                return min(max((Double(index) + Double(within)) / Double(steps), 0), 1)
            }
            start = end
        }
        return 1
    }

    private func cell(at index: Int) -> some View {
        let current = min(steps - 1, Int(progress * Double(steps)))
        let hasStarted = progress > 0
        let shape = RoundedRectangle(cornerRadius: 1, style: .continuous)

        return shape
            .fill(fillColor(index: index, current: current, hasStarted: hasStarted))
            .overlay(shape.stroke(borderColor(index: index, current: current, hasStarted: hasStarted), lineWidth: 1))
    }

    /// 書き入れ前の短冊は白紙(持ち上がった紙色)。濁った鼠を置かない。
    private func fillColor(index: Int, current: Int, hasStarted: Bool) -> Color {
        guard hasStarted else { return YagyoPrintColor.paperRaised }
        if index < current { return YagyoPrintColor.vermillion }
        if index == current { return YagyoPrintColor.persimmon }
        return YagyoPrintColor.paperRaised
    }

    private func borderColor(index: Int, current: Int, hasStarted: Bool) -> Color {
        guard hasStarted else { return YagyoPrintColor.inkMuted }
        if index < current { return YagyoPrintColor.vermillionInk }
        if index == current { return YagyoPrintColor.ink }
        return YagyoPrintColor.inkMuted
    }
}

/// 灯芯 — 音量の自前スライダー。明治大正の計器を思わせる「罫と丸紋」の意匠:
/// 単罫+四半目盛のトラック、通過側は柿色の実線、ノブは丸紋(生成り+
/// 焦茶の輪+柿色の芯)。フラット塗りで、ドラッグ中は芯がわずかに広がる
/// (Reduce Motion時は変化なし)。StepProgressBar と同族。
struct TomoshibiSlider: View {
    @Binding var value: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isDragging = false

    /// VoiceOver `.adjustable` の一歩(5%)。
    static let nudgeStep = 0.05

    /// 提灯玉ノブの直径。ノブ中心の可動域 [r, width - r] が値域0〜1に対応する。
    static let knobDiameter: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let midY = geometry.size.height / 2
            let knobRadius = Self.knobDiameter / 2
            let knobCenterX = knobRadius + CGFloat(value) * max(0, width - Self.knobDiameter)
            let coreDiameter: CGFloat = isDragging && !reduceMotion ? 7 : 5

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(YagyoPrintColor.inkMuted)
                    .frame(height: 2)

                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { mark in
                    Rectangle()
                        .fill(YagyoPrintColor.inkMuted)
                        .frame(width: 1.5, height: 7)
                        .position(
                            x: knobRadius + CGFloat(mark) * max(0, width - Self.knobDiameter),
                            y: midY
                        )
                }

                Rectangle()
                    .fill(YagyoPrintColor.persimmon)
                    .frame(width: max(knobCenterX, 2), height: 2)

                Circle()
                    .fill(YagyoPrintColor.paperRaised)
                    .overlay(Circle().stroke(YagyoPrintColor.ink, lineWidth: 1.5))
                    .overlay(
                        Circle()
                            .fill(YagyoPrintColor.persimmon)
                            .frame(width: coreDiameter, height: coreDiameter)
                    )
                    .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                    .position(x: knobCenterX, y: midY)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                value = Self.fraction(at: location.x, width: width)
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { drag in
                        value = Self.fraction(at: drag.location.x, width: width)
                    }
            )
        }
        // 見た目の14ptノブは保ち、透明な操作面だけを44ptへ広げる。
        .frame(height: YagyoPrintMetrics.controlHitTarget)
        .accessibilityElement()
        .accessibilityLabel("音量")
        .accessibilityValue("\(Int(value * 100))パーセント")
        .accessibilityAdjustableAction { direction in
            value = Self.nudged(value, direction: direction)
        }
    }

    /// タップ/ドラッグ位置を0〜1の値へ写す。ノブ中心の可動域 [r, width - r] を
    /// 値域に対応させ、表示側(knobCenterX)の逆写像にする — ノブ上から
    /// ドラッグを始めても値が跳ばない。可動域が無いときは0。
    static func fraction(at x: CGFloat, width: CGFloat) -> Double {
        let travel = width - knobDiameter
        guard travel > 0 else { return 0 }
        return min(max(Double((x - knobDiameter / 2) / travel), 0), 1)
    }

    /// VoiceOverの増減一歩。0〜1で留める。
    static func nudged(_ value: Double, direction: AccessibilityAdjustmentDirection) -> Double {
        let delta = direction == .increment ? nudgeStep : -nudgeStep
        return min(max(value + delta, 0), 1)
    }
}
