import SwiftUI

extension Color {
    /// 0xRRGGBB のリテラルから色を作る — Web版CSSの色をそのまま写せるように。
    init(yagyoHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

/// 音反応・妖怪・夜空がすでに使っている意味色。
/// Dayモードの画面表層は `YagyoPrintColor` を使い、この契約は一括置換しない。
enum YagyoColor {
    static let sumi = Color(yagyoHex: 0x0b0c14)          // 墨 — 夜の地
    static let yoiyami = Color(yagyoHex: 0x151726)       // 宵闇 — パネル
    static let yoiyami2 = Color(yagyoHex: 0x1d2033)
    static let geppaku = Color(yagyoHex: 0xe9e4d3)       // 月白 — 文字
    static let chochin = Color(yagyoHex: 0xf0a63c)       // 提灯 — アクセント
    static let shu = Color(yagyoHex: 0xc2402e)           // 朱 — 通常打
    static let kitsunebi = Color(yagyoHex: 0x6fd3e0)     // 狐火 — ゴースト
    static let line = Color(yagyoHex: 0x2c3047)
    static let dim = Color(yagyoHex: 0x8a8fa8)

    // 丑三つ時
    static let ushiSumi = Color(yagyoHex: 0x120a18)
    static let ushiTitle = Color(yagyoHex: 0xf0d9d9)
    static let akaMoon = Color(yagyoHex: 0xd84040)

    // セル(ステップシーケンサー由来)
    static let cellEmpty = Color(yagyoHex: 0x1b1e2e)
    static let cellStrongBorder = Color(yagyoHex: 0xffc46a)
    static let cellHitBorder = Color(yagyoHex: 0xe0604a)

    static let footerInk = Color(yagyoHex: 0x4a4f66)
}

/// 生成り紙へ限定色を刷る、画面表層専用のDayモード色。
/// `teal` は分析値と分析状態に限定し、通常メタデータや広い面へ使わない。
enum YagyoPrintColor {
    static let canvas = Color(yagyoHex: 0xf2e6cb)
    static let paper = Color(yagyoHex: 0xe8d7b5)
    static let paperRaised = Color(yagyoHex: 0xf5ecd8)
    static let paperMuted = Color(yagyoHex: 0xb9a98c)
    /// 丑三つ時など、局所的に紙面が暮れる状態だけで使う。
    static let stage = Color(yagyoHex: 0x554c46)
    static let ink = Color(yagyoHex: 0x35241e)
    static let inkMuted = Color(yagyoHex: 0x6b5748)
    /// 藍摺。大面積の背景にはせず、版木枠・外題・細い色版へ限定する。
    static let indigo = Color(yagyoHex: 0x283b4a)
    static let indigoMuted = Color(yagyoHex: 0x647983)
    static let vermillion = Color(yagyoHex: 0xc94f35)
    static let vermillionInk = Color(yagyoHex: 0xa43d27)
    static let persimmon = Color(yagyoHex: 0xd77a3d)
    static let teal = Color(yagyoHex: 0x1b6666)
    static let tealRule = Color(yagyoHex: 0x6f8c84)
    static let brass = Color(yagyoHex: 0xb88a45)
}

enum YagyoPrintMetrics {
    static let ruleWidth: CGFloat = 1
    static let innerRuleInset: CGFloat = 4
    static let panelRadius: CGFloat = 12
    static let rowRadius: CGFloat = 8
    static let frameCut: CGFloat = 8
    static let controlHitTarget: CGFloat = 44
}

/// 妖怪欄間の色。Dayは紙上、丑三つ時だけ局所的に夜へ入る。
struct ParadePalette {
    let skyTop: Color
    let skyBottom: Color
    let moon: Color
    let halo: Color
    let fog: Color

    static let day = ParadePalette(
        skyTop: YagyoPrintColor.paperRaised,
        skyBottom: YagyoPrintColor.paper,
        moon: YagyoPrintColor.persimmon,
        halo: YagyoPrintColor.persimmon.opacity(0.10),
        fog: YagyoPrintColor.inkMuted.opacity(0.055)
    )

    static let ushimitsu = ParadePalette(
        skyTop: Color(yagyoHex: 0x160a1c),
        skyBottom: Color(yagyoHex: 0x2a1035),
        moon: YagyoColor.akaMoon,
        halo: YagyoColor.akaMoon.opacity(0.16),
        fog: Color(yagyoHex: 0xc878a0).opacity(0.06)
    )
}

/// 浮世絵の版木枠と引札の外郭を共通化する切り角形。
/// `InsettableShape` なので、主役面だけは同じ形の二重罫を安全に重ねられる。
struct WoodblockFrameShape: InsettableShape {
    var cut: CGFloat = YagyoPrintMetrics.frameCut
    private var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard insetRect.width > 0, insetRect.height > 0 else { return Path() }

        let resolvedCut = min(
            max(0, cut - insetAmount * 0.35),
            min(insetRect.width, insetRect.height) / 3
        )

        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX + resolvedCut, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX - resolvedCut, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY + resolvedCut))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - resolvedCut))
        path.addLine(to: CGPoint(x: insetRect.maxX - resolvedCut, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX + resolvedCut, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.maxY - resolvedCut))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + resolvedCut))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> WoodblockFrameShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

enum ModernRetroPanelTone: Equatable, Sendable {
    case paper
    case stage

    fileprivate var fill: Color {
        switch self {
        case .paper: YagyoPrintColor.paper
        case .stage: YagyoPrintColor.stage
        }
    }

    fileprivate var outerRule: Color {
        switch self {
        case .paper: YagyoPrintColor.indigo
        case .stage: YagyoPrintColor.ink
        }
    }

    fileprivate var innerRule: Color {
        switch self {
        case .paper: YagyoPrintColor.paperMuted
        case .stage: YagyoPrintColor.paper
        }
    }
}

/// 支えとなる紙面。主役の版木枠と競合しないよう単罫に留める。
/// glass/material/shadowは使わない。
struct ModernRetroPanel: ViewModifier {
    var tone: ModernRetroPanelTone = .paper
    var radius: CGFloat = YagyoPrintMetrics.panelRadius
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = WoodblockFrameShape(cut: min(radius, YagyoPrintMetrics.frameCut))

        content
            .padding(padding)
            .background(tone.fill, in: shape)
            .overlay {
                shape.stroke(tone.outerRule, lineWidth: YagyoPrintMetrics.ruleWidth)
            }
    }
}

enum RetroPlaqueTone: Equatable, Sendable {
    case paper
    case stage
    case seal

    fileprivate var fill: Color {
        switch self {
        case .paper: YagyoPrintColor.paperRaised
        case .stage: YagyoPrintColor.stage
        case .seal: YagyoPrintColor.vermillionInk
        }
    }

    fileprivate var foreground: Color {
        switch self {
        case .paper: YagyoPrintColor.ink
        case .stage, .seal: YagyoPrintColor.paperRaised
        }
    }

    fileprivate var innerRule: Color {
        switch self {
        case .paper: YagyoPrintColor.paperMuted
        case .stage: YagyoPrintColor.paper
        case .seal: YagyoPrintColor.paperRaised
        }
    }
}

/// 画面・主要パネルの見出し札。内容のDynamic Typeサイズを固定しない。
struct RetroPlaque<Content: View>: View {
    var tone: RetroPlaqueTone = .paper
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 9
    private let content: () -> Content

    init(
        tone: RetroPlaqueTone = .paper,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 9,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tone = tone
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content
    }

    var body: some View {
        let shape = WoodblockFrameShape(cut: YagyoPrintMetrics.frameCut)

        content()
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tone.fill, in: shape)
            .overlay {
                shape.stroke(
                    tone == .paper ? YagyoPrintColor.indigo : YagyoPrintColor.ink,
                    lineWidth: YagyoPrintMetrics.ruleWidth
                )
                shape
                    .inset(by: YagyoPrintMetrics.innerRuleInset)
                    .stroke(tone.innerRule, lineWidth: YagyoPrintMetrics.ruleWidth)
            }
    }
}

/// 長い情報面だけを区切る、中央丸紋付きの単罫。
struct RetroDivider: View {
    var color: Color = YagyoPrintColor.tealRule

    var body: some View {
        HStack(spacing: 7) {
            Rectangle()
                .fill(color)
                .frame(height: YagyoPrintMetrics.ruleWidth)
            Rectangle()
                .rotation(.degrees(45))
                .fill(YagyoPrintColor.canvas)
                .overlay(
                    Rectangle()
                        .rotation(.degrees(45))
                        .stroke(color, lineWidth: YagyoPrintMetrics.ruleWidth)
                )
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(color)
                .frame(height: YagyoPrintMetrics.ruleWidth)
        }
        .accessibilityHidden(true)
    }
}

enum RetroIconButtonShape: Equatable, Sendable {
    case circle
    case seal

    fileprivate var radius: CGFloat {
        switch self {
        case .circle: YagyoPrintMetrics.controlHitTarget / 2
        case .seal: YagyoPrintMetrics.rowRadius
        }
    }
}

/// SF Symbolと44pt操作領域を保った、丸紋／角印の小操作。
struct RetroIconButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var accent: Color = YagyoPrintColor.indigo
    var shape: RetroIconButtonShape = .circle
    var action: () -> Void

    var body: some View {
        let outline = shape == .circle
            ? AnyShape(Circle())
            : AnyShape(WoodblockFrameShape(cut: YagyoPrintMetrics.frameCut))

        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(
                    minWidth: YagyoPrintMetrics.controlHitTarget,
                    minHeight: YagyoPrintMetrics.controlHitTarget
                )
                .foregroundStyle(accent)
                .background(YagyoPrintColor.paperRaised, in: outline)
                .overlay {
                    outline.stroke(accent, lineWidth: YagyoPrintMetrics.ruleWidth)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    func modernRetroPanel(
        tone: ModernRetroPanelTone = .paper,
        radius: CGFloat = YagyoPrintMetrics.panelRadius,
        padding: CGFloat = 16
    ) -> some View {
        modifier(ModernRetroPanel(tone: tone, radius: radius, padding: padding))
    }
}
