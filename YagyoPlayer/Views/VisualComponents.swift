import SwiftUI

struct YagyoBackdrop: View {
    var isUshimitsu: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: isUshimitsu
                    ? [
                        YagyoColor.ushiSumi,
                        Color(yagyoHex: 0x1d0e26),
                        YagyoColor.ushiSumi
                    ]
                    : [
                        YagyoColor.sumi,
                        Color(yagyoHex: 0x11131f),
                        YagyoColor.sumi
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Canvas { context, size in
                // 遠くの星 — 静かに散らす
                for index in 0..<40 {
                    let seed = Double(index)
                    let x = Self.fract(sin(seed * 12.9898) * 43758.5453) * size.width
                    let y = Self.fract(sin(seed * 78.233) * 12543.123) * size.height * 0.6
                    let alpha = 0.03 + Self.fract(sin(seed * 3.7) * 951.135) * 0.06
                    context.fill(
                        Path(CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(YagyoColor.geppaku.opacity(alpha))
                    )
                }

                // 靄の筋
                for index in 0..<18 {
                    let y = size.height * CGFloat(index) / 17
                    let alpha = 0.04 + Double(index % 4) * 0.01
                    var path = Path()
                    path.move(to: CGPoint(x: -20, y: y))
                    path.addCurve(
                        to: CGPoint(x: size.width + 20, y: y + CGFloat(index % 3) * 14),
                        control1: CGPoint(x: size.width * 0.22, y: y - 20),
                        control2: CGPoint(x: size.width * 0.72, y: y + 24)
                    )
                    context.stroke(path, with: .color(YagyoColor.line.opacity(alpha)), lineWidth: 1)
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
}

struct CircularWaveform: View {
    var progress: Double
    var level: Double = 0
    var activity: ParadeSignalSnapshot.Activity
    var levelBand: ParadeSignalSnapshot.LevelBand

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let presentation = CircularWaveformPresentation(
            activity: activity,
            levelBand: levelBand
        )

        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.35
            let count = 76

            for index in 0..<count {
                let normalized = Double(index) / Double(count)
                let angle = normalized * .pi * 2 - .pi / 2
                let length: CGFloat
                if reduceMotion || !presentation.usesProgressPhase {
                    length = CGFloat(presentation.staticLength)
                } else {
                    let pulse = sin((normalized * 8 + progress * 3.5) * .pi * 2)
                    let sway = 6 + level * 16
                    length = CGFloat(12 + (pulse + 1) * sway)
                }
                let inner = radius - length * 0.35
                let outer = radius + length

                var path = Path()
                path.move(to: point(center: center, radius: inner, angle: angle))
                path.addLine(to: point(center: center, radius: outer, angle: angle))

                let color: Color
                if presentation.usesAccentColor {
                    color = index % 11 == 0 ? YagyoColor.kitsunebi : YagyoColor.geppaku
                } else {
                    color = YagyoColor.dim
                }
                let lineWidth: CGFloat = presentation == .unavailable ? 1.2 : (index % 11 == 0 ? 2.2 : 1.4)
                let dash: [CGFloat] = presentation == .unavailable ? [2, 2] : []
                context.stroke(
                    path,
                    with: .color(color.opacity(lineOpacity(for: presentation))),
                    style: StrokeStyle(lineWidth: lineWidth, dash: dash)
                )
            }

            let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let ringColor = presentation.usesAccentColor ? YagyoColor.chochin : YagyoColor.dim
            let ringDash: [CGFloat] = presentation == .unavailable ? [3, 3] : []
            context.stroke(
                ring,
                with: .color(ringColor.opacity(presentation == .stopped ? 0.32 : 0.52)),
                style: StrokeStyle(lineWidth: 1, dash: ringDash)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lineOpacity(for presentation: CircularWaveformPresentation) -> Double {
        switch presentation {
        case .stopped:
            0.32
        case .unavailable:
            0.52
        case .low:
            reduceMotion ? 0.42 : 0.86
        case .medium:
            reduceMotion ? 0.64 : 0.86
        case .high:
            0.86
        }
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

/// ステップシーケンサー風の再生位置バー — Web版のグリッドのマスをそのまま
/// シークバーに。過ぎたマスは朱、いま鳴っているマスは提灯色に灯る。
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
                        .frame(width: cellWidth)
                        .padding(.leading, index % 4 == 0 && index > 0 ? groupGap : 0)
                }
            }
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
        .frame(height: 30)
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
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return shape
            .fill(fillColor(index: index, current: current, hasStarted: hasStarted))
            .overlay(shape.stroke(borderColor(index: index, current: current, hasStarted: hasStarted), lineWidth: 1))
            .shadow(
                color: hasStarted && index == current ? YagyoColor.chochin.opacity(0.5) : .clear,
                radius: 5
            )
    }

    private func fillColor(index: Int, current: Int, hasStarted: Bool) -> Color {
        guard hasStarted else { return YagyoColor.cellEmpty }
        if index < current { return YagyoColor.shu }
        if index == current { return YagyoColor.chochin }
        return YagyoColor.cellEmpty
    }

    private func borderColor(index: Int, current: Int, hasStarted: Bool) -> Color {
        guard hasStarted else { return YagyoColor.line }
        if index < current { return YagyoColor.cellHitBorder }
        if index == current { return YagyoColor.cellStrongBorder }
        return YagyoColor.line
    }
}

/// 灯芯 — 音量の自前スライダー。標準Sliderの白い丸ノブを提灯玉に置き換え、
/// 通過側の線が提灯色にほのかに灯る。StepProgressBar と同族の意匠。
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
            let knobRadius = Self.knobDiameter / 2
            let knobCenterX = knobRadius + CGFloat(value) * max(0, width - Self.knobDiameter)
            let glowsStronger = isDragging && !reduceMotion

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(YagyoColor.line)
                    .frame(height: 2)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [YagyoColor.chochin.opacity(0.16), YagyoColor.chochin.opacity(0.62)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(knobCenterX, 2), height: 2)
                    .shadow(color: YagyoColor.chochin.opacity(0.3), radius: 3)

                Circle()
                    .fill(YagyoColor.chochin)
                    .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                    .shadow(
                        color: YagyoColor.chochin.opacity(glowsStronger ? 0.75 : 0.45),
                        radius: glowsStronger ? 8 : 5
                    )
                    .position(x: knobCenterX, y: geometry.size.height / 2)
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
        .frame(height: 33)
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
