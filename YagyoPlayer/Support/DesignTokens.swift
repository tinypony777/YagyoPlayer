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

/// 夜行絵巻の空模様 — 常夜と丑三つ時。
struct ParadePalette {
    let skyTop: Color
    let skyBottom: Color
    let moon: Color
    let halo: Color
    let fog: Color

    static let day = ParadePalette(
        skyTop: Color(yagyoHex: 0x070812),
        skyBottom: Color(yagyoHex: 0x141830),
        moon: YagyoColor.geppaku,
        halo: YagyoColor.geppaku.opacity(0.10),
        fog: Color(yagyoHex: 0xb2bcdc).opacity(0.05)
    )

    static let ushimitsu = ParadePalette(
        skyTop: Color(yagyoHex: 0x160a1c),
        skyBottom: Color(yagyoHex: 0x2a1035),
        moon: YagyoColor.akaMoon,
        halo: YagyoColor.akaMoon.opacity(0.16),
        fog: Color(yagyoHex: 0xc878a0).opacity(0.06)
    )
}

struct RitualPanel: ViewModifier {
    var radius: CGFloat = 24
    var padding: CGFloat = 16
    var tint: Color = YagyoColor.chochin.opacity(0.12)

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .padding(padding)
            .background {
                shape
                    .fill(YagyoColor.yoiyami.opacity(0.78))
                    .overlay(shape.stroke(YagyoColor.line.opacity(0.9), lineWidth: 1))
            }
            .ritualGlass(shape: shape, tint: tint)
    }
}

private extension View {
    @ViewBuilder
    func ritualGlass(shape: RoundedRectangle, tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    func ritualPanel(radius: CGFloat = 24, padding: CGFloat = 16, tint: Color = YagyoColor.chochin.opacity(0.12)) -> some View {
        modifier(RitualPanel(radius: radius, padding: padding, tint: tint))
    }
}
