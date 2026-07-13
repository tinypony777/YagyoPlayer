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
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 1.2), value: isUshimitsu)
    }

    private static func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}

enum CircularWaveformPresentation: Equatable, Sendable {
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

    var usesProgressPhase: Bool {
        switch self {
        case .stopped, .unavailable:
            false
        case .low, .medium, .high:
            true
        }
    }

    var staticLength: Double {
        switch self {
        case .stopped: 12
        case .unavailable: 20
        case .low: 14
        case .medium: 23
        case .high: 32
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
}

struct CircularWaveform: View {
    var progress: Double
    var level: Double = 0
    var activity: ParadeSignalSnapshot.Activity
    var levelBand: ParadeSignalSnapshot.LevelBand
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        let presentation = CircularWaveformPresentation(
            activity: activity,
            levelBand: levelBand
        )

        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let centerMarkSize = max(42, min(side * 0.27, 70))

            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let discRadius = min(size.width, size.height) * 0.46
                    let innerRingRadius = discRadius - 6
                    let tickOuterRadius = discRadius * 0.78
                    let progressRadius = discRadius - 3
                    let clampedProgress = min(max(progress, 0), 1)
                    let clampedLevel = min(max(level, 0), 1)

                    let discRect = CGRect(
                        x: center.x - discRadius,
                        y: center.y - discRadius,
                        width: discRadius * 2,
                        height: discRadius * 2
                    )
                    context.fill(Path(ellipseIn: discRect), with: .color(YagyoPrintColor.paper))

                    let outerRing = Path(ellipseIn: discRect)
                    let innerRing = Path(
                        ellipseIn: CGRect(
                            x: center.x - innerRingRadius,
                            y: center.y - innerRingRadius,
                            width: innerRingRadius * 2,
                            height: innerRingRadius * 2
                        )
                    )
                    let ringDash: [CGFloat] = presentation == .unavailable ? [4, 3] : []
                    context.stroke(
                        outerRing,
                        with: .color(YagyoPrintColor.ink),
                        style: StrokeStyle(lineWidth: 1.5, dash: ringDash)
                    )
                    context.stroke(
                        innerRing,
                        with: .color(YagyoPrintColor.inkMuted),
                        style: StrokeStyle(lineWidth: 1, dash: ringDash)
                    )

                    let count = 48
                    for index in 0..<count {
                        if presentation == .unavailable, !index.isMultiple(of: 4) {
                            continue
                        }

                        let normalized = Double(index) / Double(count)
                        let angle = CGFloat(normalized * .pi * 2 - .pi / 2)
                        let baseLength = CGFloat(presentation.staticLength)
                        let animatedAddition: CGFloat
                        if reduceMotion || !presentation.usesProgressPhase {
                            animatedAddition = 0
                        } else {
                            let pulse = sin((normalized * 8 + clampedProgress * 3.5) * .pi * 2)
                            animatedAddition = CGFloat((pulse + 1) * (2 + clampedLevel * 6))
                        }
                        let hierarchyAddition: CGFloat
                        if index.isMultiple(of: 12) {
                            hierarchyAddition = 5
                        } else if index.isMultiple(of: 4) {
                            hierarchyAddition = 2
                        } else {
                            hierarchyAddition = 0
                        }
                        let length = min(
                            baseLength + animatedAddition + hierarchyAddition,
                            max(8, tickOuterRadius - centerMarkSize * 0.58)
                        )

                        var tick = Path()
                        tick.move(to: point(center: center, radius: tickOuterRadius - length, angle: angle))
                        tick.addLine(to: point(center: center, radius: tickOuterRadius, angle: angle))

                        let isMajor = index.isMultiple(of: 12)
                        let tickColor = presentation == .high && isMajor
                            ? YagyoPrintColor.vermillion
                            : YagyoPrintColor.ink
                        let width: CGFloat = isMajor ? 2.2 : (index.isMultiple(of: 4) ? 1.5 : 1)
                        context.stroke(
                            tick,
                            with: .color(tickColor.opacity(lineOpacity(for: presentation))),
                            lineWidth: width
                        )
                    }

                    var progressArc = Path()
                    progressArc.addArc(
                        center: center,
                        radius: progressRadius,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * clampedProgress),
                        clockwise: false
                    )
                    context.stroke(
                        progressArc,
                        with: .color(YagyoPrintColor.vermillion),
                        style: StrokeStyle(lineWidth: 4, lineCap: .butt)
                    )

                    let endpointAngle = CGFloat(clampedProgress * .pi * 2 - .pi / 2)
                    let endpoint = point(center: center, radius: progressRadius, angle: endpointAngle)
                    let endpointRect = CGRect(x: endpoint.x - 5, y: endpoint.y - 5, width: 10, height: 10)
                    context.fill(
                        Path(ellipseIn: endpointRect),
                        with: .color(YagyoPrintColor.persimmon)
                    )
                    context.stroke(
                        Path(ellipseIn: endpointRect),
                        with: .color(YagyoPrintColor.ink),
                        lineWidth: 1
                    )
                }

                Text(presentation.centerMark)
                    .font(.system(size: max(18, side * 0.12), weight: .semibold, design: .serif))
                    .foregroundStyle(YagyoPrintColor.ink)
                    .frame(width: centerMarkSize, height: centerMarkSize)
                    .background(YagyoPrintColor.paperRaised, in: Circle())
                    .overlay {
                        Circle().stroke(YagyoPrintColor.ink, lineWidth: 1)
                        Circle()
                            .inset(by: 4)
                            .stroke(YagyoPrintColor.paperMuted, lineWidth: 1)
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lineOpacity(for presentation: CircularWaveformPresentation) -> Double {
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

    private func point(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

/// 16本の短冊目盛による再生位置。過ぎた目盛は朱、現在位置は柿色で示す。
struct StepProgressBar: View {
    var progress: Double
    var isEnabled: Bool
    var onScrub: (Double) -> Void

    private let steps = 16
    private let spacing: CGFloat = 3
    private let groupGap: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let cellWidth = max(1, (width - spacing * CGFloat(steps - 1) - groupGap * 3) / CGFloat(steps))
            HStack(spacing: spacing) {
                ForEach(0..<steps, id: \.self) { index in
                    cell(at: index)
                        .frame(width: cellWidth, height: index.isMultiple(of: 4) ? 11 : 7)
                        .padding(.leading, index % 4 == 0 && index > 0 ? groupGap : 0)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard isEnabled else { return }
                onScrub(fraction(at: location.x, cellWidth: cellWidth))
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        onScrub(fraction(at: value.location.x, cellWidth: cellWidth))
                    },
                including: isEnabled ? .all : .subviews
            )
        }
        // 短冊の見た目は7/11ptのまま、scrub操作面だけを44pt確保する。
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

    /// タップ/ドラッグ位置をセル配置(3ptの目 + 拍頭8ptの間)に沿って割合へ写す。
    private func fraction(at x: CGFloat, cellWidth: CGFloat) -> Double {
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

    private func fillColor(index: Int, current: Int, hasStarted: Bool) -> Color {
        guard hasStarted else { return YagyoPrintColor.paperMuted }
        if index < current { return YagyoPrintColor.vermillion }
        if index == current { return YagyoPrintColor.persimmon }
        return YagyoPrintColor.paperMuted
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
